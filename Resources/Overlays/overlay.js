// Connects to /ws, keeps the latest state, renders the bug for its slot every frame from the master clock fields.
// The clock maths mirrors ScorebugCore/ClockEngine.swift. Keep them in step.
(function () {
  const body = document.body;
  const orientation = body.dataset.orientation === "v" ? "v" : "h";
  const slot = parseInt(body.dataset.slot, 10) || 1;
  const bug = document.getElementById("bug");
  const q = (sel) => bug.querySelector(sel);
  const el = {
    homeCode: q(".team.home .code"), awayCode: q(".team.away .code"),
    homeCrest: q(".team.home .crest"), awayCrest: q(".team.away .crest"),
    homeScore: q(".score.home"), awayScore: q(".score.away"),
    clock: q(".clock"), clockMain: q(".clock .main"), clockState: q(".clock .state"),
    addedPlus: q(".added .plus"), addedCounter: q(".added .counter"),
    kicksHome: q(".kicks.home"), kicksAway: q(".kicks.away"),
    tallyHome: q(".tally .home"), tallyAway: q(".tally .away"),
    scorersHome: q(".scorers .list.home"), scorersAway: q(".scorers .list.away"),
    themeCss: document.getElementById("theme-css"),
  };

  let state = null;          // latest snapshot
  let match = null;          // this slot's match
  let theme = null;          // theme.json
  let themeId = null;
  let renderedRevision = -1;
  let lastGoalKey = null;
  let skewMs = 0;            // serverTime - Date.now() at receipt

  const PERIOD = { firstHalf: [0, 2700], secondHalf: [2700, 5400], extraFirst: [5400, 6300], extraSecond: [6300, 7200] };
  const STATE_LABEL = { preMatch: "KO", halfTime: "HT", fullTime: "FT", extraBreak: "HT", extraFullTime: "AET", shootout: "PENS", finished: "FT" };
  const LAST_END = { halfTime: 2700, fullTime: 5400, extraBreak: 6300, extraFullTime: 7200, shootout: 7200, finished: 7200 };

  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function fmt(seconds) { const s = Math.max(0, Math.floor(seconds)); return pad(Math.floor(s / 60)) + ":" + pad(s % 60); }
  function now() { return (Date.now() + skewMs) / 1000; }
  function elapsed(clock) {
    let total = clock.periodBaseSeconds + clock.accumulated;
    if (clock.running && clock.periodStart) total += Math.max(0, now() - clock.periodStart / 1000);
    return total;
  }
  function clockDisplay(m, style) {
    const e = elapsed(m.clock);
    const p = PERIOD[m.phase];
    if (!p) {
      const shown = m.phase === "preMatch" ? "00:00" : fmt(Math.min(e, LAST_END[m.phase] || 0));
      return { main: shown, added: null, counter: null, state: STATE_LABEL[m.phase] || null };
    }
    const added = m.addedMinutes ? "+" + m.addedMinutes : null;
    if (style === "runOn") return { main: fmt(e), added, counter: null, state: null };
    const main = fmt(Math.min(e, p[1]));
    const counter = added && e > p[1] ? fmt(e - p[1]) : null;
    return { main, added, counter, state: null };
  }

  function competitionFor(m) { return (state.competitions || []).find((c) => c.id === m.competitionId); }

  function loadTheme(id) {
    if (id === themeId) return;
    themeId = id;
    body.dataset.theme = id;
    el.themeCss.href = "/themes/" + id + "/theme.css?v=" + Date.now();
    fetch("/themes/" + id + "/theme.json").then((r) => r.ok ? r.json() : null).then((t) => {
      theme = t;
      applyGeometry();
    }).catch(() => { theme = null; });
  }
  function applyGeometry() {
    const g = theme && theme.geometry && theme.geometry[orientation];
    if (!g) return;
    if (g.left != null) bug.style.setProperty("--bug-left", g.left + "px");
    if (g.top != null) bug.style.setProperty("--bug-top", g.top + "px");
    if (g.maxWidth != null) bug.style.setProperty("--bug-max-width", g.maxWidth + "px");
    if (g.scale != null) bug.style.setProperty("--bug-scale", String(g.scale));
  }

  function setCrest(node, team) {
    if (team.crestFile) {
      node.classList.remove("monogram");
      node.textContent = "";
      node.style.backgroundImage = "url(/crests/" + encodeURIComponent(team.crestFile) + ")";
      node.style.background = "";
      node.style.backgroundImage = "url(/crests/" + encodeURIComponent(team.crestFile) + ")";
    } else {
      node.classList.add("monogram");
      node.style.backgroundImage = "";
      node.style.background = team.primaryColour;
      node.style.color = team.textColour;
      node.textContent = (team.code || "?").slice(0, 2);
    }
  }

  function renderStatic(m) {
    const comp = competitionFor(m);
    loadTheme(comp ? comp.themeId : m.competitionId);
    bug.style.setProperty("--home-primary", m.home.primaryColour);
    bug.style.setProperty("--home-secondary", m.home.secondaryColour);
    bug.style.setProperty("--home-text", m.home.textColour);
    bug.style.setProperty("--away-primary", m.away.primaryColour);
    bug.style.setProperty("--away-secondary", m.away.secondaryColour);
    bug.style.setProperty("--away-text", m.away.textColour);
    el.homeCode.textContent = m.home.code;
    el.awayCode.textContent = m.away.code;
    setCrest(el.homeCrest, m.home);
    setCrest(el.awayCrest, m.away);
    el.homeScore.textContent = m.homeScore;
    el.awayScore.textContent = m.awayScore;
    bug.classList.toggle("hidden", !m.visible);
    bug.classList.toggle("has-added", !!m.addedMinutes && !!PERIOD[m.phase]);
    bug.dataset.phase = m.phase;

    const s = m.shootout;
    bug.classList.toggle("has-shootout", m.phase === "shootout" && !!s);
    if (s) {
      renderKicks(el.kicksHome, s, "home");
      renderKicks(el.kicksAway, s, "away");
      el.tallyHome.textContent = s.kicks.filter((k) => k.side === "home" && k.result === "scored").length;
      el.tallyAway.textContent = s.kicks.filter((k) => k.side === "away" && k.result === "scored").length;
    }

    renderScorers(el.scorersHome, m.goals.filter((g) => g.side === "home"));
    renderScorers(el.scorersAway, m.goals.filter((g) => g.side === "away"));

    const key = m.lastGoal ? m.lastGoal.goalId : null;
    if (key && key !== lastGoalKey) {
      const box = m.lastGoal.side === "home" ? el.homeScore : el.awayScore;
      box.classList.remove("goal"); void box.offsetWidth; box.classList.add("goal");
      bug.classList.add("goal-" + m.lastGoal.side);
      setTimeout(() => bug.classList.remove("goal-" + m.lastGoal.side), 4000);
    }
    lastGoalKey = key;
  }
  function renderKicks(node, s, side) {
    const kicks = s.kicks.filter((k) => k.side === side);
    const slots = Math.max(5, kicks.length);
    node.innerHTML = "";
    for (let i = 0; i < slots; i++) {
      const d = document.createElement("span");
      d.className = "kick " + (kicks[i] ? kicks[i].result : "pending");
      node.appendChild(d);
    }
  }
  function renderScorers(node, goals) {
    node.innerHTML = "";
    const byName = new Map();
    goals.forEach((g) => {
      const name = g.scorer || "Goal";
      const label = g.minuteLabel + (g.penalty ? " pen" : "") + (g.ownGoal ? " og" : "");
      if (!byName.has(name)) byName.set(name, []);
      byName.get(name).push(label);
    });
    byName.forEach((mins, name) => {
      const e = document.createElement("div");
      e.className = "entry";
      e.textContent = name + " " + mins.join(", ");
      node.appendChild(e);
    });
  }

  // Scorers strap: shown periodically while goals exist and the bug is visible.
  function scorersVisible(m) {
    if (!m.goals.length || m.phase === "preMatch") return false;
    const every = (theme && theme.scorersEverySeconds) || 90;
    const dur = (theme && theme.scorersForSeconds) || 8;
    const t = now() % every;
    return t < dur;
  }

  function frame() {
    if (match) {
      const style = (theme && theme.clockStyle) || "freezeAndCount";
      const d = clockDisplay(match, style);
      el.clockMain.textContent = d.main;
      el.clock.classList.toggle("stopped", !!d.state);
      el.clockState.textContent = d.state || "";
      el.clock.classList.toggle("running", !!match.clock.running);
      el.addedPlus.textContent = d.added || "";
      el.addedCounter.textContent = d.counter || "";
      bug.classList.toggle("has-counter", !!d.counter);
      bug.classList.toggle("show-scorers", scorersVisible(match));
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  function accept(snapshot) {
    state = snapshot;
    skewMs = snapshot.serverTime - Date.now();
    const m = snapshot.matches.find((x) => x.slot === slot);
    if (!m) return;
    match = m;
    if (m.revision !== renderedRevision) { renderStatic(m); renderedRevision = m.revision; }
  }

  let retry = 500;
  function connect() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    const ws = new WebSocket(proto + "://" + location.host + "/ws");
    ws.onmessage = (ev) => { try { accept(JSON.parse(ev.data)); retry = 500; } catch (e) { console.error(e); } };
    ws.onclose = () => { setTimeout(connect, retry); retry = Math.min(retry * 2, 8000); };
    ws.onerror = () => ws.close();
  }
  connect();
  // Belt and braces: a full re-sync every 30 seconds in case a message was lost.
  setInterval(() => fetch("/api/state").then((r) => r.json()).then(accept).catch(() => {}), 30000);
})();
