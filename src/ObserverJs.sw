module ObserverJs

# GENERATED from src/observer.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() {
    "/* Swarm Observer - client. Source of truth for src/ObserverJs.sw\n" ++
    "   (python3 scripts/embed_js.py src/observer.js ObserverJs src/ObserverJs.sw).\n" ++
    "\n" ++
    "   ~4 frames/s from the server, sampled from the live node:\n" ++
    "     n   process count          sc  scheduler count\n" ++
    "     sch [[id, procs_run_delta, steals_delta, idle_waits_delta], ...]\n" ++
    "     tot [spawns, crashes, restarts, dropped]   dl  the same, as deltas this frame\n" ++
    "     p   [[pid, parent, status, mailbox, memKB, recv_delta, sent_delta, name], ...]\n" ++
    "         status 0 waiting, 1 running, 2 runnable; name is 0 when unnamed\n" ++
    "     k   1 if the server allows killing a process from the UI\n" ++
    "   Everything is process_list / process_info / swarm_stats. Nothing is simulated. */\n" ++
    "(function () {\n" ++
    "  var $ = function (id) { return document.getElementById(id); };\n" ++
    "  var cv = $('map-cv');\n" ++
    "  if (!cv) return;\n" ++
    "  var g = cv.getContext('2d');\n" ++
    "  var dpr = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "  var W = 0, H = 0;\n" ++
    "\n" ++
    "  var COLORS = { run: [59, 158, 255], wait: [82, 90, 105], runnable: [245, 166, 35], red: [255, 77, 77], green: [80, 227, 194] };\n" ++
    "  var procs = {}, groups = {}, ghosts = [], pops = [];\n" ++
    "  var layoutDirty = true, structSig = '';\n" ++
    "  var selected = 0, hover = 0, killable = 0, tab = 'mail';\n" ++
    "  var last = null, lastT = 0, dt = 250, first = true, framesN = 0, fps = 0, fpsT = performance.now();\n" ++
    "  var hist = { proc: [], msg: [], rs: [], cr: [], sch: [] };\n" ++
    "  var selHist = { mail: [], mem: [], rate: [] };\n" ++
    "  var stats = {};                       /* animated counters: id -> {cur, tgt, fmt} */\n" ++
    "  var feed = [];\n" ++
    "\n" ++
    "  /* ---------- helpers ---------- */\n" ++
    "  function fmt(n) { n = Math.round(n || 0); if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k'; return String(n); }\n" ++
    "  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }\n" ++
    "  function kb(n) { return n >= 1024 ? (n / 1024).toFixed(1) + ' MB' : Math.round(n) + ' KB'; }\n" ++
    "  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }\n" ++
    "  function rgba(c, a) { return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }\n" ++
    "  function ease(t) { return 1 - Math.pow(1 - t, 3); }\n" ++
    "  function back(t) { var c1 = 1.9, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); }\n" ++
    "  function label(p) { return p.name || ('process ' + p.pid); }\n" ++
    "  function groupName(pid) {\n" ++
    "    var c = groups[pid]; return c ? c.label : '#' + pid;\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- sizing ---------- */\n" ++
    "  function resize() {\n" ++
    "    var box = $('map'); if (!box) return;\n" ++
    "    W = box.clientWidth; H = box.clientHeight;\n" ++
    "    cv.width = Math.max(1, W * dpr); cv.height = Math.max(1, H * dpr);\n" ++
    "    cv.style.width = W + 'px'; cv.style.height = H + 'px';\n" ++
    "    g.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    layoutDirty = true;\n" ++
    "  }\n" ++
    "  if (window.ResizeObserver) new ResizeObserver(resize).observe($('map')); else window.addEventListener('resize', resize);\n" ++
    "  resize();\n" ++
    "\n" ++
    "  /* ---------- cluster layout: phyllotaxis inside, spiral packing between ---------- */\n" ++
    "  var SP = 9.2, GAP = 14;\n" ++
    "  function slotPos(k) { var a = k * 2.399963, r = SP * Math.sqrt(k + 0.6); return [r * Math.cos(a), r * Math.sin(a)]; }\n" ++
    "  function relayout() {\n" ++
    "    var gs = [], key, i, j;\n" ++
    "    for (key in groups) gs.push(groups[key]);\n" ++
    "    if (!gs.length || W < 50) return;\n" ++
    "    gs.forEach(function (c) { c.r = SP * Math.sqrt(c.cap + 1) + 10; c.tx = NaN; });\n" ++
    "    gs.sort(function (a, b) { return b.r - a.r; });\n" ++
    "    var placed = [];\n" ++
    "    for (i = 0; i < gs.length; i++) {\n" ++
    "      var c = gs[i], done = false;\n" ++
    "      if (!placed.length) { c.tx = 0; c.ty = 0; placed.push(c); continue; }\n" ++
    "      for (var rad = 0; !done && rad < 6000; rad += 5) {\n" ++
    "        var steps = Math.max(12, Math.ceil(rad / 6));\n" ++
    "        for (var s = 0; s < steps; s++) {\n" ++
    "          var ang = s / steps * 6.2832, x = rad * Math.cos(ang), y = rad * Math.sin(ang), ok = true;\n" ++
    "          for (j = 0; j < placed.length; j++) {\n" ++
    "            var dx = x - placed[j].tx, dy = y - placed[j].ty;\n" ++
    "            if (Math.sqrt(dx * dx + dy * dy) < c.r + placed[j].r + GAP) { ok = false; break; }\n" ++
    "          }\n" ++
    "          if (ok) { c.tx = x; c.ty = y; placed.push(c); done = true; break; }\n" ++
    "        }\n" ++
    "      }\n" ++
    "      if (!done) { c.tx = 0; c.ty = 0; }\n" ++
    "    }\n" ++
    "    var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;\n" ++
    "    gs.forEach(function (c) { x0 = Math.min(x0, c.tx - c.r); x1 = Math.max(x1, c.tx + c.r); y0 = Math.min(y0, c.ty - c.r - 22); y1 = Math.max(y1, c.ty + c.r); });\n" ++
    "    var pad = 36, aw = W - pad * 2, ah = H - pad * 2 - 20;\n" ++
    "    var sc = Math.max(0.2, Math.min(aw / Math.max(1, x1 - x0), ah / Math.max(1, y1 - y0), 2.4));\n" ++
    "    var mx = (x0 + x1) / 2, my = (y0 + y1) / 2;\n" ++
    "    gs.forEach(function (c) {\n" ++
    "      c.sx = W / 2 + (c.tx - mx) * sc; c.sy = H / 2 + 6 + (c.ty - my) * sc; c.sc = sc;\n" ++
    "      if (c.x === undefined) { c.x = c.sx; c.y = c.sy; c.z = sc; }\n" ++
    "    });\n" ++
    "    layoutDirty = false;\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- slots ---------- */\n" ++
    "  function assign(p) {\n" ++
    "    var c = groups[p.parent];\n" ++
    "    if (!c) { c = groups[p.parent] = { used: {}, cap: 0, n: 0, label: '', key: p.parent }; layoutDirty = true; }\n" ++
    "    var k = 0; while (c.used[k]) k++;\n" ++
    "    c.used[k] = p.pid; p.slot = k; c.n++;\n" ++
    "    if (k + 1 > c.cap) c.cap = Math.max(k + 1, Math.ceil(c.cap * 1.3));\n" ++
    "  }\n" ++
    "  function release(p) {\n" ++
    "    var c = groups[p.parent];\n" ++
    "    if (c && p.slot >= 0) { delete c.used[p.slot]; c.n--; }\n" ++
    "    p.slot = -1;\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- frames ---------- */\n" ++
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  window.SwEvents.obs = function (d) {\n" ++
    "    var now = performance.now(), i, row, p, seen = {};\n" ++
    "    if (lastT) dt = Math.max(100, Math.min(1000, now - lastT));\n" ++
    "    lastT = now; last = d; killable = d.k || 0; framesN++;\n" ++
    "    var births = {}, deaths = {};\n" ++
    "    for (i = 0; i < d.p.length; i++) {\n" ++
    "      row = d.p[i]; seen[row[0]] = 1; p = procs[row[0]];\n" ++
    "      if (!p) { p = procs[row[0]] = { pid: row[0], heat: 0, slot: -1, born: now, parent: -1 }; if (!first) pops.push(p); }\n" ++
    "      var par = row[1] || 0;\n" ++
    "      if (p.parent !== par) {\n" ++
    "        if (p.slot >= 0) release(p);\n" ++
    "        var wasNew = p.parent === -1; p.parent = par;\n" ++
    "        if (wasNew && !first) births[par] = (births[par] || 0) + 1;\n" ++
    "      }\n" ++
    "      p.status = row[2]; p.mail = row[3]; p.mem = row[4];\n" ++
    "      p.recv = row[5] * 1000 / dt; p.sent = row[6] * 1000 / dt; p.rate = p.recv + p.sent; p.name = row[7] || '';\n" ++
    "      p.heat += (Math.min(1, p.rate / 80) - p.heat) * 0.5;\n" ++
    "      if (p.slot < 0) assign(p);\n" ++
    "    }\n" ++
    "    for (var pid in procs) {\n" ++
    "      if (seen[pid]) continue;\n" ++
    "      var q = procs[pid];\n" ++
    "      ghosts.push({ x: q.px, y: q.py, t: now, c: d.dl[1] > 0 ? COLORS.red : COLORS.wait });\n" ++
    "      deaths[q.parent] = (deaths[q.parent] || 0) + 1;\n" ++
    "      release(q); delete procs[pid]; if (selected == pid) { selected = 0; selHist = { mail: [], mem: [], rate: [] }; }\n" ++
    "    }\n" ++
    "    for (var gk in groups) if (!groups[gk].n) { delete groups[gk]; layoutDirty = true; }\n" ++
    "    for (gk in groups) {\n" ++
    "      var par2 = procs[gk], nm = '';\n" ++
    "      if (gk == 0) nm = 'node'; else if (par2 && par2.name && par2.name !== 'sw_dynsup') nm = par2.name; else nm = 'children of #' + gk;\n" ++
    "      groups[gk].label = nm;\n" ++
    "    }\n" ++
    "    var sig = Object.keys(groups).map(function (k) { return k + ':' + groups[k].cap; }).join(',');\n" ++
    "    if (sig !== structSig) { structSig = sig; layoutDirty = true; }\n" ++
    "\n" ++
    "    /* activity feed: one plain-language line per group per frame */\n" ++
    "    if (!first) {\n" ++
    "      for (var b in births) addFeed('spawn', '<b>' + births[b] + '</b> spawned in <em>' + esc(groupName(b)) + '</em>');\n" ++
    "      for (var x in deaths) {\n" ++
    "        if (d.dl[1] > 0) addFeed('crash', '<b>' + deaths[x] + '</b> crashed in <em>' + esc(groupName(x)) + '</em>' + (d.dl[2] > 0 ? ', supervisor restarted ' + d.dl[2] : ''));\n" ++
    "        else addFeed('exit', '<b>' + deaths[x] + '</b> exited in <em>' + esc(groupName(x)) + '</em>');\n" ++
    "      }\n" ++
    "    }\n" ++
    "\n" ++
    "    /* history for the sparklines / inspector */\n" ++
    "    var msgs = 0; for (i = 0; i < d.p.length; i++) msgs += d.p[i][5];\n" ++
    "    push(hist.proc, d.n); push(hist.msg, msgs * 1000 / dt); push(hist.rs, d.dl[2] * 1000 / dt); push(hist.cr, d.dl[1] * 1000 / dt);\n" ++
    "    var run = 0; for (i = 0; i < d.sch.length; i++) run += d.sch[i][1]; push(hist.sch, run * 1000 / dt);\n" ++
    "    var sp = procs[selected]; if (sp) { push(selHist.mail, sp.mail); push(selHist.mem, sp.mem); push(selHist.rate, sp.rate); }\n" ++
    "\n" ++
    "    setStat('proc', d.n, fmtc, d.dl[0] ? '+' + fmt(d.dl[0] * 1000 / dt) + ' spawned/s' : 'steady', d.dl[0] ? 'up' : '');\n" ++
    "    setStat('msg', msgs * 1000 / dt, fmt, 'messages delivered / s', '');\n" ++
    "    setStat('rs', d.tot[2], fmtc, d.dl[2] ? '+' + fmt(d.dl[2] * 1000 / dt) + '/s restarting' : 'supervisors idle', d.dl[2] ? 'warn' : '');\n" ++
    "    setStat('cr', d.tot[1], fmtc, d.dl[1] ? '+' + fmt(d.dl[1] * 1000 / dt) + '/s crashing' : 'no crashes now', d.dl[1] ? 'bad' : '');\n" ++
    "    setStat('sch', d.sc, fmtc, d.tot[3] ? fmt(d.tot[3]) + ' msgs dropped' : 'no messages dropped', d.tot[3] ? 'bad' : '');\n" ++
    "    first = false;\n" ++
    "    renderSide();\n" ++
    "  };\n" ++
    "  window.SwEvents.viewers = function (n) { if ($('o-view')) $('o-view').textContent = n; };\n" ++
    "  function push(a, v) { a.push(v); if (a.length > 90) a.shift(); }\n" ++
    "\n" ++
    "  /* ---------- animated counters ---------- */\n" ++
    "  function setStat(id, v, f, sub, tone) {\n" ++
    "    var s = stats[id] || (stats[id] = { cur: v, tgt: v, shown: '' });\n" ++
    "    s.tgt = v; s.fmt = f;\n" ++
    "    var d = $('d-' + id); if (d) { d.textContent = sub; d.className = 'chip ' + (tone || ''); }\n" ++
    "  }\n" ++
    "  function tickStats() {\n" ++
    "    for (var id in stats) {\n" ++
    "      var s = stats[id]; s.cur += (s.tgt - s.cur) * 0.2; if (Math.abs(s.tgt - s.cur) < 0.5) s.cur = s.tgt;\n" ++
    "      var t = s.fmt(s.cur), el = $('v-' + id);\n" ++
    "      if (el && t !== s.shown) { el.textContent = t; s.shown = t; }\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- sparklines ---------- */\n" ++
    "  function spark(id, arr, color) {\n" ++
    "    var c = $(id); if (!c || arr.length < 2) return;\n" ++
    "    var w = c.clientWidth, h = c.clientHeight, r = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "    if (c.width !== w * r) { c.width = w * r; c.height = h * r; }\n" ++
    "    var x = c.getContext('2d'); x.setTransform(r, 0, 0, r, 0, 0); x.clearRect(0, 0, w, h);\n" ++
    "    var lo = Math.min.apply(null, arr), hi = Math.max.apply(null, arr), n = arr.length, i;\n" ++
    "    if (hi - lo < 1e-9) { hi = lo + 1; }\n" ++
    "    function X(k) { return k / Math.max(1, n - 1) * w; }\n" ++
    "    function Y(k) { return h - 4 - ((arr[k] - lo) / (hi - lo)) * (h - 10); }\n" ++
    "    var gr = x.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, rgba(color, 0.28)); gr.addColorStop(1, rgba(color, 0));\n" ++
    "    x.beginPath(); x.moveTo(0, h);\n" ++
    "    for (i = 0; i < n; i++) x.lineTo(X(i), Y(i));\n" ++
    "    x.lineTo(w, h); x.closePath(); x.fillStyle = gr; x.fill();\n" ++
    "    x.beginPath(); for (i = 0; i < n; i++) { if (i === 0) x.moveTo(X(i), Y(i)); else x.lineTo(X(i), Y(i)); }\n" ++
    "    x.strokeStyle = rgba(color, 0.95); x.lineWidth = 1.5; x.stroke();\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- side panels ---------- */\n" ++
    "  function addFeed(kind, html) {\n" ++
    "    feed.unshift({ kind: kind, html: html, t: Date.now() }); if (feed.length > 40) feed.pop();\n" ++
    "    var el = $('o-feed'); if (!el) return;\n" ++
    "    var d = document.createElement('div'); d.className = 'ev ' + kind; d.setAttribute('data-t', Date.now());\n" ++
    "    d.innerHTML = '<i></i><span>' + html + '</span><time>now</time>';\n" ++
    "    el.insertBefore(d, el.firstChild);\n" ++
    "    while (el.children.length > 40) el.removeChild(el.lastChild);\n" ++
    "  }\n" ++
    "  function ageFeed() {\n" ++
    "    var el = $('o-feed'); if (!el) return; var now = Date.now();\n" ++
    "    for (var i = 0; i < el.children.length; i++) {\n" ++
    "      var t = el.children[i].getAttribute('data-t'), s = Math.round((now - t) / 1000), tm = el.children[i].lastChild;\n" ++
    "      if (tm) tm.textContent = s < 2 ? 'now' : s < 60 ? s + 's' : Math.floor(s / 60) + 'm';\n" ++
    "    }\n" ++
    "  }\n" ++
    "  setInterval(ageFeed, 1000);\n" ++
    "\n" ++
    "  function renderSide() {\n" ++
    "    if (!last) return;\n" ++
    "    var d = last, i, h = '';\n" ++
    "    /* tabs */\n" ++
    "    var arr = []; for (var pid in procs) arr.push(procs[pid]);\n" ++
    "    var items, val, mxv = 1, sub;\n" ++
    "    if (tab === 'mail') { items = arr.filter(function (p) { return p.mail >= 8; }).sort(function (a, b) { return b.mail - a.mail; }); val = function (p) { return p.mail; }; sub = function (p) { return fmtc(p.mail) + ' queued'; }; }\n" ++
    "    else if (tab === 'hot') { items = arr.filter(function (p) { return p.rate > 0.5; }).sort(function (a, b) { return b.rate - a.rate; }); val = function (p) { return p.rate; }; sub = function (p) { return fmt(p.rate) + ' msg/s'; }; }\n" ++
    "    else { items = arr.slice().sort(function (a, b) { return b.mem - a.mem; }); val = function (p) { return p.mem; }; sub = function (p) { return kb(p.mem); }; }\n" ++
    "    items = items.slice(0, 6);\n" ++
    "    if (items.length) mxv = Math.max(1, val(items[0]));\n" ++
    "    for (i = 0; i < items.length; i++) {\n" ++
    "      var p = items[i], w = Math.max(3, val(p) / mxv * 100);\n" ++
    "      h += '<div class=\"li' + (p.pid == selected ? ' on' : '') + '\" data-pid=\"' + p.pid + '\"><div class=\"lt\"><span>' + esc(p.name || ('process ' + p.pid)) + '</span><b>' + sub(p) + '</b></div>' +\n" ++
    "           '<div class=\"bar\"><i style=\"width:' + w + '%\"></i></div><div class=\"ls\">' + esc(groupName(p.parent)) + ' &middot; #' + p.pid + '</div></div>';\n" ++
    "    }\n" ++
    "    $('o-list').innerHTML = h || '<div class=\"empty\">' + (tab === 'mail' ? 'No process has a backlog. Healthy.' : 'Nothing to show.') + '</div>';\n" ++
    "    var tabs = document.querySelectorAll('[data-tab]');\n" ++
    "    for (i = 0; i < tabs.length; i++) tabs[i].classList.toggle('on', tabs[i].getAttribute('data-tab') === tab);\n" ++
    "    /* schedulers */\n" ++
    "    var mxr = 1; for (i = 0; i < d.sch.length; i++) mxr = Math.max(mxr, d.sch[i][1]);\n" ++
    "    h = '';\n" ++
    "    for (i = 0; i < d.sch.length; i++) {\n" ++
    "      var s = d.sch[i], busy = s[1] / mxr * 100;\n" ++
    "      h += '<div class=\"sc\"><span>S' + s[0] + '</span><div class=\"bar\"><i style=\"width:' + Math.max(2, busy) + '%\"></i></div><b>' + fmt(s[1] * 1000 / dt) + ' runs/s</b></div>';\n" ++
    "    }\n" ++
    "    $('o-sch').innerHTML = h;\n" ++
    "    renderInspector();\n" ++
    "    spark('sp-proc', hist.proc, COLORS.run); spark('sp-msg', hist.msg, COLORS.green); spark('sp-rs', hist.rs, COLORS.runnable);\n" ++
    "    spark('sp-cr', hist.cr, COLORS.red); spark('sp-sch', hist.sch, COLORS.run);\n" ++
    "    var vw = $('o-fps'); if (vw) vw.textContent = fps;\n" ++
    "  }\n" ++
    "  function renderInspector() {\n" ++
    "    var box = $('o-insp'), p = procs[selected];\n" ++
    "    if (!p) { box.innerHTML = '<div class=\"empty\">Select a process on the map, or from a list, to inspect it.</div>'; return; }\n" ++
    "    var st = ['waiting', 'running', 'runnable'][p.status] || '?', cls = ['wait', 'run', 'runnable'][p.status] || 'wait';\n" ++
    "    var parent = procs[p.parent];\n" ++
    "    box.innerHTML = '<div class=\"ih\"><div><h4>' + esc(label(p)) + '</h4><div class=\"sub\">#' + p.pid + (parent ? ' &middot; child of <a data-pid=\"' + parent.pid + '\">' + esc(label(parent)) + '</a>' : '') + '</div></div><span class=\"pill ' + cls + '\">' + st + '</span></div>' +\n" ++
    "      '<div class=\"kv\"><div><span>memory</span><b>' + kb(p.mem) + '</b></div><div><span>mailbox</span><b class=\"' + (p.mail > 100 ? 'bad' : '') + '\">' + fmtc(p.mail) + '</b></div><div><span>in</span><b>' + fmt(p.recv) + '/s</b></div><div><span>out</span><b>' + fmt(p.sent) + '/s</b></div></div>' +\n" ++
    "      '<div class=\"sparks2\"><div><span>mailbox depth</span><canvas id=\"si-mail\"></canvas></div><div><span>messages / s</span><canvas id=\"si-rate\"></canvas></div></div>' +\n" ++
    "      (killable ? '<button class=\"btn danger\" id=\"o-kill\">Kill process</button>' : '');\n" ++
    "    spark('si-mail', selHist.mail, COLORS.red); spark('si-rate', selHist.rate, COLORS.run);\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- input ---------- */\n" ++
    "  function pick(mx, my) {\n" ++
    "    var best = 0, bd = 150;\n" ++
    "    for (var pid in procs) {\n" ++
    "      var p = procs[pid]; if (p.px === undefined) continue;\n" ++
    "      var dx = mx - p.px, dy = my - p.py, d2 = dx * dx + dy * dy;\n" ++
    "      if (d2 < bd) { bd = d2; best = p.pid; }\n" ++
    "    }\n" ++
    "    return best;\n" ++
    "  }\n" ++
    "  function select(pid) { selected = pid || 0; selHist = { mail: [], mem: [], rate: [] }; if (procs[selected]) { selHist.mail.push(procs[selected].mail); selHist.mem.push(procs[selected].mem); selHist.rate.push(procs[selected].rate); } renderSide(); }\n" ++
    "  cv.addEventListener('mousemove', function (e) {\n" ++
    "    var r = cv.getBoundingClientRect(); hover = pick(e.clientX - r.left, e.clientY - r.top); cv.style.cursor = hover ? 'pointer' : 'default';\n" ++
    "    var tip = $('o-tip'), p = procs[hover];\n" ++
    "    if (p && tip) {\n" ++
    "      tip.style.display = 'block';\n" ++
    "      tip.innerHTML = '<b>' + esc(label(p)) + '</b><span>#' + p.pid + ' &middot; ' + esc(groupName(p.parent)) + '</span><span>' + kb(p.mem) + ' &middot; mailbox ' + fmtc(p.mail) + ' &middot; ' + fmt(p.rate) + ' msg/s</span>';\n" ++
    "      tip.style.left = Math.min(W - 230, e.clientX - r.left + 14) + 'px'; tip.style.top = Math.max(8, e.clientY - r.top - 12) + 'px';\n" ++
    "    } else if (tip) tip.style.display = 'none';\n" ++
    "  });\n" ++
    "  cv.addEventListener('mouseleave', function () { hover = 0; var t = $('o-tip'); if (t) t.style.display = 'none'; });\n" ++
    "  cv.addEventListener('mousedown', function (e) { var r = cv.getBoundingClientRect(); select(pick(e.clientX - r.left, e.clientY - r.top)); });\n" ++
    "  document.addEventListener('click', function (e) {\n" ++
    "    var t = e.target.closest ? e.target.closest('[data-pid],[data-tab],#o-kill') : null;\n" ++
    "    if (!t) return;\n" ++
    "    if (t.hasAttribute('data-tab')) { tab = t.getAttribute('data-tab'); renderSide(); return; }\n" ++
    "    if (t.id === 'o-kill') {\n" ++
    "      var p = procs[selected];\n" ++
    "      if (p) { ghosts.push({ x: p.px, y: p.py, t: performance.now(), c: COLORS.red }); window.swSend('kill', { pid: String(selected) }); }\n" ++
    "      return;\n" ++
    "    }\n" ++
    "    select(Number(t.getAttribute('data-pid')));\n" ++
    "  });\n" ++
    "\n" ++
    "  /* ---------- draw ---------- */\n" ++
    "  function draw(now) {\n" ++
    "    requestAnimationFrame(draw);\n" ++
    "    if (now - fpsT > 1000) { fps = framesN; framesN = 0; fpsT = now; var f = $('o-fps'); if (f) f.textContent = fps; }\n" ++
    "    tickStats();\n" ++
    "    if (W < 50) return;\n" ++
    "    g.clearRect(0, 0, W, H);\n" ++
    "    if (layoutDirty) relayout();\n" ++
    "    var key, c, pid, p, i;\n" ++
    "    for (key in groups) {\n" ++
    "      c = groups[key]; if (c.x === undefined) continue;\n" ++
    "      c.x += (c.sx - c.x) * 0.1; c.y += (c.sy - c.y) * 0.1; c.z += (c.sc - c.z) * 0.1;\n" ++
    "      var rr = Math.max(4, c.r * c.z), breathe = 1 + Math.sin(now / 1800 + c.key) * 0.004;\n" ++
    "      g.strokeStyle = 'rgba(255,255,255,0.07)'; g.lineWidth = 1;\n" ++
    "      g.beginPath(); g.arc(c.x, c.y, rr * breathe, 0, 6.2832); g.stroke();\n" ++
    "      g.font = '500 11px ui-sans-serif,-apple-system,\"SF Pro Text\",Inter,sans-serif'; g.textAlign = 'left';\n" ++
    "      var wl = g.measureText(c.label).width, wn = g.measureText(String(c.n)).width, tw = wl + wn + 26;\n" ++
    "      var lx = c.x - tw / 2, ly = c.y - rr - 27;\n" ++
    "      g.fillStyle = 'rgba(14,14,16,0.94)'; roundRect(lx, ly, tw, 20, 10); g.fill();\n" ++
    "      g.strokeStyle = 'rgba(255,255,255,0.11)'; g.lineWidth = 1; roundRect(lx, ly, tw, 20, 10); g.stroke();\n" ++
    "      g.fillStyle = '#a1a1a6'; g.fillText(c.label, lx + 10, ly + 14);\n" ++
    "      g.fillStyle = '#ededed'; g.fillText(String(c.n), lx + 10 + wl + 6, ly + 14);\n" ++
    "    }\n" ++
    "    /* dots */\n" ++
    "    g.globalCompositeOperation = 'lighter';\n" ++
    "    for (pid in procs) {\n" ++
    "      p = procs[pid]; c = groups[p.parent]; if (!c || p.slot < 0 || c.x === undefined) continue;\n" ++
    "      var sp = slotPos(p.slot), tx = c.x + sp[0] * c.z, ty = c.y + sp[1] * c.z;\n" ++
    "      if (p.px === undefined) { p.px = tx; p.py = ty; }\n" ++
    "      p.px += (tx - p.px) * 0.18; p.py += (ty - p.py) * 0.18;\n" ++
    "      var age = (now - p.born) / 520, pop = age >= 1 ? 1 : Math.max(0, back(age));\n" ++
    "      var rad = Math.max(2, Math.min(6.5, 1.6 + Math.log(1 + p.mem) * 0.42)) * Math.min(1.5, Math.max(0.6, c.z * 0.9)) * pop;\n" ++
    "      var base = p.status === 1 ? COLORS.run : p.status === 2 ? COLORS.runnable : COLORS.wait;\n" ++
    "      var a = 0.5 + p.heat * 0.5;\n" ++
    "      if (p.heat > 0.3) {\n" ++
    "        var gr = g.createRadialGradient(p.px, p.py, 0, p.px, p.py, rad * 4.5);\n" ++
    "        gr.addColorStop(0, rgba(COLORS.run, p.heat * 0.35)); gr.addColorStop(1, rgba(COLORS.run, 0));\n" ++
    "        g.fillStyle = gr; g.fillRect(p.px - rad * 4.5, p.py - rad * 4.5, rad * 9, rad * 9);\n" ++
    "      }\n" ++
    "      g.fillStyle = rgba(base, a); g.beginPath(); g.arc(p.px, p.py, Math.max(0.1, rad + p.heat * 1.4), 0, 6.2832); g.fill();\n" ++
    "    }\n" ++
    "    g.globalCompositeOperation = 'source-over';\n" ++
    "    /* backlog rings */\n" ++
    "    for (pid in procs) {\n" ++
    "      p = procs[pid]; if (p.mail < 8 || p.px === undefined) continue;\n" ++
    "      var lvl = Math.min(1, Math.log(1 + p.mail) / Math.log(5000));\n" ++
    "      g.strokeStyle = rgba(COLORS.red, 0.4 + lvl * 0.6); g.lineWidth = 1 + lvl * 2;\n" ++
    "      g.beginPath(); g.arc(p.px, p.py, Math.max(2, 5 + lvl * 13 + Math.sin(now / 220 + p.pid) * lvl * 1.8), 0, 6.2832); g.stroke();\n" ++
    "    }\n" ++
    "    /* selection: parent and child links */\n" ++
    "    var sel = procs[selected];\n" ++
    "    if (sel && sel.px !== undefined) {\n" ++
    "      var par = procs[sel.parent];\n" ++
    "      g.lineWidth = 1;\n" ++
    "      if (par && par.px !== undefined) { g.strokeStyle = 'rgba(255,255,255,0.5)'; g.beginPath(); g.moveTo(sel.px, sel.py); g.lineTo(par.px, par.py); g.stroke(); }\n" ++
    "      g.strokeStyle = 'rgba(59,158,255,0.2)';\n" ++
    "      for (pid in procs) { p = procs[pid]; if (p.parent === sel.pid && p.px !== undefined) { g.beginPath(); g.moveTo(sel.px, sel.py); g.lineTo(p.px, p.py); g.stroke(); } }\n" ++
    "      g.strokeStyle = '#fff'; g.lineWidth = 1.5; g.beginPath(); g.arc(sel.px, sel.py, 10 + Math.sin(now / 300) * 1, 0, 6.2832); g.stroke();\n" ++
    "    }\n" ++
    "    var hp = procs[hover];\n" ++
    "    if (hp && hp.px !== undefined && hover !== selected) { g.strokeStyle = 'rgba(255,255,255,0.7)'; g.lineWidth = 1; g.beginPath(); g.arc(hp.px, hp.py, 9, 0, 6.2832); g.stroke(); }\n" ++
    "    /* exits fade out; spawns get a soft ring */\n" ++
    "    for (i = ghosts.length - 1; i >= 0; i--) {\n" ++
    "      var gh = ghosts[i], t = (now - gh.t) / 800;\n" ++
    "      if (t >= 1 || gh.x === undefined) { ghosts.splice(i, 1); continue; }\n" ++
    "      g.strokeStyle = rgba(gh.c, (1 - t) * 0.9); g.lineWidth = 1.5 * (1 - t) + 0.3;\n" ++
    "      g.beginPath(); g.arc(gh.x, gh.y, Math.max(0.1, 3 + 26 * ease(t)), 0, 6.2832); g.stroke();\n" ++
    "      g.fillStyle = rgba(gh.c, (1 - t) * 0.5); g.beginPath(); g.arc(gh.x, gh.y, Math.max(0.1, 4 * (1 - t)), 0, 6.2832); g.fill();\n" ++
    "    }\n" ++
    "    for (i = pops.length - 1; i >= 0; i--) {\n" ++
    "      var po = pops[i], tp = (now - po.born) / 900;\n" ++
    "      if (tp >= 1) { pops.splice(i, 1); continue; }\n" ++
    "      if (po.px === undefined) continue;\n" ++
    "      g.strokeStyle = rgba(COLORS.green, (1 - tp) * 0.8); g.lineWidth = 1.5 * (1 - tp) + 0.3;\n" ++
    "      g.beginPath(); g.arc(po.px, po.py, Math.max(0.1, 2 + 22 * ease(tp)), 0, 6.2832); g.stroke();\n" ++
    "    }\n" ++
    "  }\n" ++
    "  function roundRect(x, y, w, h, r) {\n" ++
    "    g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r);\n" ++
    "    g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();\n" ++
    "  }\n" ++
    "  window.__swObserver = { procs: procs, groups: groups };\n" ++
    "  requestAnimationFrame(draw);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
