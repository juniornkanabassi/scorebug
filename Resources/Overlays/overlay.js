// Connects to /ws, keeps the latest state, renders the bug for its slot every frame from the master clock fields.
// The clock maths mirrors ScorebugCore/ClockEngine.swift. Keep them in step.
(function () {
  const body = document.body;
  const orientation = body.dataset.orientation === "v" ? "v" : "h";
  const slot = parseInt(body.dataset.slot, 10) || 1;
  const bug = document.getElementById("bug");
  const q = (sel) => bug.querySelector(sel);
  const el = {
    compLabel: q(".comp .label"),
    homeCode: q(".team.home .code"), awayCode: q(".team.away .code"),
    homeName: q(".team.home .name"), awayName: q(".team.away .name"),
    homeCrest: q(".team.home .crest"), awayCrest: q(".team.away .crest"),
    homeScore: q(".score.home"), awayScore: q(".score.away"),
    homeDigit: q(".score.home .digit"), awayDigit: q(".score.away .digit"),
    clock: q(".clock"), clockMain: q(".clock .time"), clockState: q(".clock .state"),
    addedPlus: q(".added .plus"), addedCounter: q(".added .counter"),
    kicksHome: q(".kicks.home"), kicksAway: q(".kicks.away"),
    tallyHome: q(".tally .home"), tallyAway: q(".tally .away"),
    scorersHome: q(".scorers .list.home"), scorersAway: q(".scorers .list.away"),
    themeCss: document.getElementById("theme-css"),
  };

  let state = null, match = null, theme = null, themeId = null;
  let renderedRevision = -1, lastGoalKey = null, skewMs = 0;

  // Build-in/build-out: themes animate their own children under .bug.building-in / .bug.building-out (see overlay.css).
  // null means "never seen a state yet" so the very first appearance still plays the build-in once, per the page starting hidden.
  const BUILD_MS = 820; // covers every theme's 0.5-0.8s choreography with a small buffer before the marker class is dropped
  let visibleState = null, buildTimer = null;
  function setVisible(visible) {
    if (visibleState === visible) return;
    const isFirstEver = visibleState === null;
    visibleState = visible;
    if (buildTimer) { clearTimeout(buildTimer); buildTimer = null; }
    bug.classList.remove("building-in", "building-out");
    if (visible) {
      bug.classList.remove("hidden");
      void bug.offsetWidth; // restart animations even if building-in was already mid-flight
      bug.classList.add("building-in");
      buildTimer = setTimeout(() => { bug.classList.remove("building-in"); buildTimer = null; }, BUILD_MS);
    } else if (isFirstEver) {
      bug.classList.add("hidden"); // never shown yet: nothing to take apart, just stay off
    } else {
      bug.classList.add("building-out");
      buildTimer = setTimeout(() => { bug.classList.remove("building-out"); bug.classList.add("hidden"); buildTimer = null; }, BUILD_MS);
    }
  }

  const PERIOD = { firstHalf: [0, 2700], secondHalf: [2700, 5400], extraFirst: [5400, 6300], extraSecond: [6300, 7200] };
  const STATE_LABEL = { preMatch: "KO", halfTime: "HT", fullTime: "FT", extraBreak: "HT", extraFullTime: "AET", shootout: "PENS", finished: "FT" };
  const LAST_END = { halfTime: 2700, fullTime: 5400, extraBreak: 6300, extraFullTime: 7200, shootout: 7200, finished: 7200 };

  const pad = (n) => (n < 10 ? "0" : "") + n;
  const fmt = (s) => { s = Math.max(0, Math.floor(s)); return pad(Math.floor(s / 60)) + ":" + pad(s % 60); };
  const now = () => (Date.now() + skewMs) / 1000;
  function elapsed(clock) {
    let t = clock.periodBaseSeconds + clock.accumulated;
    if (clock.running && clock.periodStart) t += Math.max(0, now() - clock.periodStart / 1000);
    return t;
  }
  function clockDisplay(m, style) {
    const e = elapsed(m.clock), p = PERIOD[m.phase];
    if (!p) return { main: m.phase === "preMatch" ? "00:00" : fmt(Math.min(e, LAST_END[m.phase] || 0)), added: null, counter: null, state: STATE_LABEL[m.phase] || null };
    const added = m.addedMinutes ? "+" + m.addedMinutes : null;
    if (style === "runOn") return { main: fmt(e), added, counter: null, state: null };
    return { main: fmt(Math.min(e, p[1])), added, counter: added && e > p[1] ? fmt(e - p[1]) : null, state: null };
  }
  const competitionFor = (m) => (state.competitions || []).find((c) => c.id === m.competitionId);

  function loadTheme(id) {
    if (id === themeId) return;
    themeId = id; body.dataset.theme = id;
    el.themeCss.href = "/themes/" + id + "/theme.css?v=" + Date.now();
    fetch("/themes/" + id + "/theme.json").then((r) => (r.ok ? r.json() : null)).then((t) => { theme = t; body.dataset.family = (t && t.family) || ""; applyGeometry(); }).catch(() => { theme = null; });
  }
  function applyGeometry() {
    const g = theme && theme.geometry && theme.geometry[orientation];
    if (!g) return;
    if (g.left != null) bug.style.setProperty("--bug-left", g.left + "px");
    // Slot 2 in portrait sits below slot 1's bug, not on top of it; top2 (default top + slot 1's scaled height + 24px gap)
    // is measured per theme and stored in theme.json. Landscape slot 2 reuses the same top and left inset (mirrored to the right edge in CSS).
    const top = orientation === "v" && slot === 2 && g.top2 != null ? g.top2 : g.top;
    if (top != null) bug.style.setProperty("--bug-top", top + "px");
    if (g.maxWidth != null) bug.style.setProperty("--bug-max-width", g.maxWidth + "px");
    bug.style.setProperty("--bug-scale", String(g.scale != null ? g.scale : 1));
  }
  const badCrests = new Set();
  function setCrest(node, team) {
    if (team.crestFile && !badCrests.has(team.crestFile)) {
      const url = "/crests/" + encodeURIComponent(team.crestFile);
      node.classList.remove("monogram"); node.textContent = ""; node.style.background = "";
      node.style.backgroundImage = "url(" + url + ")";
      const probe = new Image();
      probe.onerror = () => { badCrests.add(team.crestFile); setCrest(node, Object.assign({}, team, { crestFile: null })); };
      probe.src = url;
    } else {
      node.classList.add("monogram"); node.style.backgroundImage = "";
      node.style.background = team.primaryColour; node.style.color = team.textColour;
      node.textContent = (team.code || "?").slice(0, 2);
    }
  }
  function renderStatic(m) {
    const comp = competitionFor(m);
    loadTheme(m.themeId || (comp ? comp.themeId : m.competitionId));
    el.compLabel.textContent = comp ? comp.shortName : "";
    const logo = comp && comp.logoFile ? "url(/crests/" + encodeURIComponent(comp.logoFile) + ")" : "none";
    bug.style.setProperty("--comp-logo", logo);
    bug.classList.toggle("has-comp-logo", logo !== "none");
    for (const [side, t] of [["home", m.home], ["away", m.away]]) {
      bug.style.setProperty("--" + side + "-crest", t.crestFile ? "url(/crests/" + encodeURIComponent(t.crestFile) + ")" : "none");
      bug.style.setProperty("--" + side + "-primary", t.primaryColour);
      bug.style.setProperty("--" + side + "-secondary", t.secondaryColour);
      bug.style.setProperty("--" + side + "-text", t.textColour);
    }
    el.homeCode.textContent = m.home.code; el.awayCode.textContent = m.away.code;
    el.homeName.textContent = m.home.shortName || m.home.name; el.awayName.textContent = m.away.shortName || m.away.name;
    setCrest(el.homeCrest, m.home); setCrest(el.awayCrest, m.away);
    for (const [box, digit, value] of [[el.homeScore, el.homeDigit, m.homeScore], [el.awayScore, el.awayDigit, m.awayScore]]) {
      if (digit.textContent !== String(value) && renderedRevision !== -1) { box.classList.remove("roll"); void box.offsetWidth; box.classList.add("roll"); }
      digit.textContent = value;
    }
    setVisible(!!m.visible);
    bug.classList.toggle("has-added", !!m.addedMinutes && !!PERIOD[m.phase]);
    bug.dataset.phase = m.phase;
    const s = m.shootout;
    bug.classList.toggle("has-shootout", m.phase === "shootout" && !!s);
    if (s) {
      renderKicks(el.kicksHome, s, "home"); renderKicks(el.kicksAway, s, "away");
      el.tallyHome.textContent = s.kicks.filter((k) => k.side === "home" && k.result === "scored").length;
      el.tallyAway.textContent = s.kicks.filter((k) => k.side === "away" && k.result === "scored").length;
    }
    renderScorers(el.scorersHome, m.goals.filter((g) => g.side === "home"));
    renderScorers(el.scorersAway, m.goals.filter((g) => g.side === "away"));
    const key = m.lastGoal ? m.lastGoal.goalId : null;
    if (key && key !== lastGoalKey && renderedRevision !== -1) {
      const box = m.lastGoal.side === "home" ? el.homeScore : el.awayScore;
      box.classList.remove("goal"); void box.offsetWidth; box.classList.add("goal");
      bug.style.setProperty("--goal-crest", "var(--" + m.lastGoal.side + "-crest)");
      bug.style.setProperty("--goal-primary", "var(--" + m.lastGoal.side + "-primary)");
      bug.style.setProperty("--goal-text", "var(--" + m.lastGoal.side + "-text)");
      bug.classList.remove("goal"); void bug.offsetWidth;
      bug.classList.add("goal-" + m.lastGoal.side, "goal");
      setTimeout(() => bug.classList.remove("goal"), 4200);
      setTimeout(() => bug.classList.remove("goal-" + m.lastGoal.side), 4000);
    }
    lastGoalKey = key;
  }
  function renderKicks(node, s, side) {
    const kicks = s.kicks.filter((k) => k.side === side), slots = Math.max(5, kicks.length);
    node.innerHTML = "";
    for (let i = 0; i < slots; i++) { const d = document.createElement("span"); d.className = "kick " + (kicks[i] ? kicks[i].result : "pending"); node.appendChild(d); }
  }
  function renderScorers(node, goals) {
    node.innerHTML = "";
    const byName = new Map();
    goals.forEach((g) => { const n = g.scorer || "Goal"; const l = g.minuteLabel + (g.penalty ? " pen" : "") + (g.ownGoal ? " og" : ""); if (!byName.has(n)) byName.set(n, []); byName.get(n).push(l); });
    byName.forEach((mins, name) => { const e = document.createElement("div"); e.className = "entry"; e.textContent = name + " " + mins.join(", "); node.appendChild(e); });
  }
  function scorersVisible(m) {
    if (!m.goals.length || m.phase === "preMatch") return false;
    const every = (theme && theme.scorersEverySeconds) || 90, dur = (theme && theme.scorersForSeconds) || 8;
    return now() % every < dur;
  }
  let demoForceScorers = false; // set by ?demo=scorers, for layout QA screenshots
  function frame() {
    if (match) {
      const d = clockDisplay(match, (theme && theme.clockStyle) || "freezeAndCount");
      el.clockMain.textContent = d.main;
      el.clock.classList.toggle("stopped", !!d.state); el.clockState.textContent = d.state || "";
      el.clock.classList.toggle("running", !!match.clock.running);
      el.addedPlus.textContent = d.added || ""; el.addedCounter.textContent = d.counter || "";
      bug.classList.toggle("has-counter", !!d.counter);
      bug.classList.toggle("show-scorers", demoForceScorers || scorersVisible(match));
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  function accept(snapshot) {
    state = snapshot; skewMs = snapshot.serverTime - Date.now();
    const m = snapshot.matches.find((x) => x.slot === slot);
    if (!m) return;
    match = m;
    if (m.revision !== renderedRevision) { renderStatic(m); renderedRevision = m.revision; }
  }
  // Debug hook for screenshots and QA: /overlay/h/1?demo=goal:home:1200 fires a goal animation on first render and freezes it at 1200 ms.
  // /overlay/*/1?demo=show:600 replays the build-in from scratch and freezes it at 600 ms.
  // /overlay/*/1?demo=scorers forces the scorers strap on (class show-scorers) for layout QA.
  const demo = new URLSearchParams(location.search).get("demo");
  if (demo) {
    const [kind, p1, p2] = demo.split(":");
    setTimeout(() => {
      if (!match) return;
      let at = null;
      if (kind === "goal") {
        const side = p1; at = p2;
        bug.style.setProperty("--goal-crest", "var(--" + (side || "home") + "-crest)");
        bug.style.setProperty("--goal-primary", "var(--" + (side || "home") + "-primary)");
        bug.style.setProperty("--goal-text", "var(--" + (side || "home") + "-text)");
        bug.classList.add("goal-" + (side || "home"), "goal");
        const box = side === "away" ? el.awayScore : el.homeScore; box.classList.add("roll");
      } else if (kind === "show") {
        at = p1;
        // No follow-up timer here (unlike the real setVisible flow): under headless capture with a virtual clock,
        // a queued removal of .building-in can fire in the same accelerated tick as the pause below, wiping the
        // frozen frame before it is ever painted. The demo path is QA-only, so just freeze and leave it be.
        if (buildTimer) { clearTimeout(buildTimer); buildTimer = null; }
        bug.classList.remove("hidden", "building-out");
        void bug.offsetWidth;
        bug.classList.add("building-in");
        visibleState = true;
      } else if (kind === "scorers") {
        demoForceScorers = true;
        bug.classList.add("show-scorers");
      }
      if (at) requestAnimationFrame(() => document.getAnimations().forEach((a) => { a.pause(); a.currentTime = parseInt(at, 10); }));
    }, 900);
  }

  let retry = 500;
  function connect() {
    const ws = new WebSocket((location.protocol === "https:" ? "wss" : "ws") + "://" + location.host + "/ws");
    ws.onmessage = (ev) => { try { accept(JSON.parse(ev.data)); retry = 500; } catch (e) { console.error(e); } };
    ws.onclose = () => { setTimeout(connect, retry); retry = Math.min(retry * 2, 8000); };
    ws.onerror = () => ws.close();
  }
  connect();
  setInterval(() => fetch("/api/state").then((r) => r.json()).then(accept).catch(() => {}), 30000);
})();
