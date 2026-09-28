// Connects to /ws, keeps the latest state, renders the bug for its slot every frame from the master clock fields.
// Club name to a stable slug for per-club CSS (accents stripped, lowercase, dashes): "AS Saint-Étienne" -> "as-saint-etienne".
// Club slug for per-club goal motifs (themes/*/clubs/<slug>.css). Letters NFKD cannot decompose
// (ø, æ, ß, ł, đ) are mapped by hand first, so "FK Bodø/Glimt" becomes "fk-bodo-glimt", not "fk-bod-glimt".
const slug = (s) => (s || "").replace(/[øØ]/g, "o").replace(/[æÆ]/g, "ae").replace(/ß/g, "ss").replace(/[łŁ]/g, "l").replace(/[đĐ]/g, "d").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
// The clock maths mirrors ScorebugCore/ClockEngine.swift. Keep them in step.
// Relative luminance (sRGB) of a #RRGGBB colour, 0 black to 1 white.
function luminance(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || "");
  if (!m) return 0;
  const n = parseInt(m[1], 16), c = [n >> 16, (n >> 8) & 255, n & 255].map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
// Ink for text drawn on a team's secondary colour: white on a dark one; on a light one the team's own primary
// when that is dark enough, else near-black. Arsenal's white secondary made white Premier League digits vanish (28 Sep).
function secondaryInk(t) {
  if (luminance(t.secondaryColour) < 0.45) return "#fff";
  return luminance(t.primaryColour) < 0.25 ? t.primaryColour : "#111";
}

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
    aggHome: q(".agg .home"), aggAway: q(".agg .away"),
    kicksHome: q(".kicks.home"), kicksAway: q(".kicks.away"),
    tallyHome: q(".tally .home"), tallyAway: q(".tally .away"),
    shootoutLabel: q(".shootout .label"),
    scorersHome: q(".scorers .list.home"), scorersAway: q(".scorers .list.away"),
    themeCss: document.getElementById("theme-css"),
  };
  if (el.shootoutLabel) el.shootoutLabel.textContent = "PENS"; // absent in a user-overridden 0.7.0 shell

  let state = null, match = null, theme = null, themeId = null;
  let renderedRevision = -1, lastGoalKey = null, skewMs = 0, aggTimer = null;

  // Preview backdrop: only the app's own preview panes load with ?preview=1, so OBS's browser source (no
  // query) never creates #backdrop and its canvas stays exactly as before.
  const isPreview = new URLSearchParams(location.search).get("preview") === "1";
  let backdrop = null, backdropPath;
  function applyBackdrop(path) {
    if (!isPreview || path === backdropPath) return;
    backdropPath = path;
    if (!backdrop) { backdrop = document.createElement("div"); backdrop.id = "backdrop"; document.getElementById("stage").before(backdrop); }
    backdrop.innerHTML = ""; backdrop.className = "";
    if (!path) return;
    if (!path.includes("/")) { backdrop.className = path; return; } // a bare name is a preset class (pitch, streamer, ...)
    const isVideo = ["mp4", "mov", "webm", "m4v"].includes(path.split(".").pop().toLowerCase());
    const media = document.createElement(isVideo ? "video" : "img");
    if (isVideo) { media.autoplay = true; media.muted = true; media.loop = true; media.playsInline = true; }
    media.src = "/preview/backdrop";
    backdrop.appendChild(media);
  }

  // Build-in/build-out: themes animate their own children under .bug.building-in / .bug.building-out (see overlay.css).
  // null means "never seen a state yet" so the very first appearance still plays the build-in once, per the page starting hidden.
  const BUILD_IN_MS = 1000; // covers the wrapper's 900ms show transition and every theme's own choreography with a small buffer
  const BUILD_OUT_MS = 750; // the wrapper's take-off finishes at 700ms, so .hidden lands soon after, not a full second later
  let visibleState = null, buildTimer = null;
  function setVisible(visible) {
    if (visibleState === visible) return;
    const isFirstEver = visibleState === null;
    visibleState = visible;
    if (buildTimer) { clearTimeout(buildTimer); buildTimer = null; }
    if (visible) {
      // A show always clears building-out too, so a show pressed mid take-off restarts clean.
      bug.classList.remove("hidden", "building-out");
      void bug.offsetWidth; // restart animations even if building-in was already mid-flight
      bug.classList.add("building-in");
      buildTimer = setTimeout(() => { bug.classList.remove("building-in"); buildTimer = null; }, BUILD_IN_MS);
    } else if (isFirstEver) {
      bug.classList.add("hidden"); // never shown yet: nothing to take apart, just stay off
    } else {
      // building-out stays on until the next setVisible (not cleared here): .hidden lands on top of it so
      // .bug.building-out.hidden's transition:none snaps the collapsed pieces off instead of fading the
      // reassembled bar back in.
      bug.classList.remove("building-in");
      bug.classList.add("building-out");
      buildTimer = setTimeout(() => { bug.classList.add("hidden"); buildTimer = null; }, BUILD_OUT_MS);
    }
  }

  const PERIOD = { firstHalf: [0, 2700], secondHalf: [2700, 5400], extraFirst: [5400, 6300], extraSecond: [6300, 7200] };
  const STATE_LABEL = { preMatch: "KO", halfTime: "HT", fullTime: "FT", extraBreak: "HT", extraFullTime: "AET", shootout: "PENS", finished: "FT" };
  const LAST_END = { halfTime: 2700, fullTime: 5400, extraBreak: 6300, extraFullTime: 7200, shootout: 7200, finished: 7200 };

  const pad = (n) => (n < 10 ? "0" : "") + n;
  // theme.json "clockFormat": "m:ss" drops the leading zero of the minutes (the UEFA feed shows 4:01, not 04:01).
  const fmt = (s) => { s = Math.max(0, Math.floor(s)); const m = Math.floor(s / 60); return (theme && theme.clockFormat === "m:ss" ? String(m) : pad(m)) + ":" + pad(s % 60); };
  const now = () => (Date.now() + skewMs) / 1000;
  function elapsed(clock) {
    let t = clock.periodBaseSeconds + clock.accumulated;
    if (clock.running && clock.periodStart) t += Math.max(0, now() - clock.periodStart / 1000);
    return t;
  }
  const EXTRA_TIME_PHASES = new Set(["extraFirst", "extraBreak", "extraSecond", "extraFullTime"]);
  function clockDisplay(m, style) {
    const e = elapsed(m.clock), p = PERIOD[m.phase];
    if (!p) return { main: m.phase === "preMatch" ? "00:00" : fmt(Math.min(e, LAST_END[m.phase] || 0)), added: null, counter: null, state: STATE_LABEL[m.phase] || null, overtime: false };
    const added = m.addedMinutes ? "+" + m.addedMinutes : null;
    const overtime = e > p[1];
    if (style === "runOn") return { main: fmt(e), added, counter: null, state: null, overtime };
    return { main: fmt(Math.min(e, p[1])), added, counter: added && overtime ? fmt(e - p[1]) : null, state: null, overtime };
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
    // The app's live "portrait bug top" setting (state.overlay.portraitTop) overrides every theme's top for
    // orientation v; the secondary slot keeps the same distance below the primary that the theme defines
    // (top2 - top). No override, or orientation h, falls back to the theme's own values untouched.
    const overlayTop = orientation === "v" && state && state.overlay && typeof state.overlay.portraitTop === "number" ? state.overlay.portraitTop : null;
    let top;
    if (overlayTop != null) {
      top = slot === 2 ? overlayTop + (g.top2 != null ? g.top2 - g.top : 0) : overlayTop;
    } else {
      top = orientation === "v" && slot === 2 && g.top2 != null ? g.top2 : g.top;
    }
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
      bug.style.setProperty("--" + side + "-secondary-ink", secondaryInk(t)); // digits that stay legible on the secondary colour
      bug.style.setProperty("--" + side + "-code", JSON.stringify(t.code)); // a theme can print it with content: var(--home-code)
      // Stable per-club identifier for club-specific goal motifs: themes match [data-home-club="arsenal"].goal-home.
      bug.dataset[side + "Club"] = slug(t.name);
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
    bug.classList.toggle("has-agg", !!m.aggregate);
    if (m.aggregate) {
      // The real feed updates the chip about 300 ms after the score; the first render and a swap write at once.
      const aggHome = String(m.homeScore + m.aggregate.firstLegHome), aggAway = String(m.awayScore + m.aggregate.firstLegAway);
      const write = () => { el.aggHome.textContent = aggHome; el.aggAway.textContent = aggAway; };
      clearTimeout(aggTimer);
      if (renderedRevision !== -1 && m.lastGoal && (el.aggHome.textContent !== aggHome || el.aggAway.textContent !== aggAway)) aggTimer = setTimeout(write, 300); else write();
    }
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
    for (let i = 0; i < slots; i++) { const d = document.createElement("span"); d.className = "kick " + (kicks[i] ? kicks[i].result : "pending"); d.dataset.index = i + 1; node.appendChild(d); }
  }
  function renderScorers(node, goals) {
    node.innerHTML = "";
    const byName = new Map();
    goals.forEach((g) => { const n = g.scorer || "Goal"; const l = g.minuteLabel + (g.penalty ? " (pen)" : "") + (g.ownGoal ? " (og)" : ""); if (!byName.has(n)) byName.set(n, []); byName.get(n).push(l); });
    // One entry per scorer: <div class="entry"><span class="name">K. Mbappé</span><span class="mins">12', 45+2' (pen)</span></div>,
    // so a theme can stack the two spans as rows (the UEFA card strap) or run them inline.
    byName.forEach((mins, name) => {
      const e = document.createElement("div"); e.className = "entry";
      const n = document.createElement("span"); n.className = "name"; n.textContent = name;
      const t = document.createElement("span"); t.className = "mins"; t.textContent = mins.join(", ");
      e.append(n, " ", t); node.appendChild(e);
    });
  }
  let demoForceScorers = false; // set by ?demo=scorers, for layout QA screenshots
  function frame() {
    if (match) {
      const d = clockDisplay(match, (theme && theme.clockStyle) || "freezeAndCount");
      if (el.clockMain.textContent !== d.main) el.clockMain.textContent = d.main;
      el.clock.classList.toggle("stopped", !!d.state); if (el.clockState.textContent !== (d.state || "")) el.clockState.textContent = d.state || "";
      el.clock.classList.toggle("running", !!match.clock.running);
      if (el.addedPlus.textContent !== (d.added || "")) el.addedPlus.textContent = d.added || "";
      if (el.addedCounter.textContent !== (d.counter || "")) el.addedCounter.textContent = d.counter || "";
      bug.classList.toggle("has-counter", !!d.counter);
      el.clock.classList.toggle("overtime", !!d.overtime);
      bug.classList.toggle("overtime", !!d.overtime);
      bug.classList.toggle("extra-time", EXTRA_TIME_PHASES.has(match.phase));
      bug.classList.toggle("show-scorers", demoForceScorers || !!match.showScorers);
    }
  }
  // Clock text only changes once a second, so a 4Hz interval (not a 60Hz rAF loop) is enough for every OBS
  // source and preview pane; accept() calls frame() once more so a command paints at once, not up to 250ms late.
  setInterval(frame, 250);
  function accept(snapshot) {
    state = snapshot; skewMs = snapshot.serverTime - Date.now();
    applyBackdrop(snapshot.overlay && snapshot.overlay.previewBackdrop);
    const m = snapshot.matches.find((x) => x.slot === slot);
    if (!m) return;
    match = m;
    if (m.revision !== renderedRevision) { renderStatic(m); renderedRevision = m.revision; }
    frame();
  }
  // Debug hook for screenshots and QA: /overlay/h/1?demo=goal:home:1200 fires a goal animation on first render and freezes it at 1200 ms.
  // /overlay/*/1?demo=show:600 replays the build-in from scratch and freezes it at 600 ms.
  // /overlay/*/1?demo=hide:300 starts from visible, plays the build-out and freezes it at 300 ms.
  // /overlay/*/1?demo=scorers forces the scorers strap on (class show-scorers) for layout QA.
  const demo = new URLSearchParams(location.search).get("demo");
  if (demo) {
    const [kind, p1, p2] = demo.split(":");
    setTimeout(() => {
      if (!match) return;
      let at = null;
      if (kind === "goal") {
        const side = p1; at = p2;
        if (buildTimer) { clearTimeout(buildTimer); buildTimer = null; }
        bug.classList.remove("hidden", "building-in", "building-out");
        visibleState = true;
        bug.style.transition = "none";
        bug.style.opacity = "1";
        void bug.offsetWidth;
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
      } else if (kind === "hide") {
        at = p1;
        if (buildTimer) { clearTimeout(buildTimer); buildTimer = null; }
        bug.classList.remove("hidden", "building-in");
        bug.classList.add("building-out");
        visibleState = false;
      } else if (kind === "scorers") {
        demoForceScorers = true;
        bug.classList.add("show-scorers");
      }
      if (at !== null) requestAnimationFrame(() => document.getAnimations().forEach((a) => { a.pause(); a.currentTime = parseInt(at, 10); }));
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
