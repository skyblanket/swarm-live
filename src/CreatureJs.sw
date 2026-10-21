module CreatureJs

# GENERATED from src/creature.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() {
    "/* Creature - client. Source of truth for src/CreatureJs.sw\n" ++
    "   (python3 scripts/embed_js.py src/creature.js CreatureJs src/CreatureJs.sw).\n" ++
    "\n" ++
    "   One frame per 25 ms tick:\n" ++
    "     s   ids of neurons that spiked        mo  motor flags [forward, turn+, turn-, boost]\n" ++
    "     ex  what the expert would do          x,y,hx,hy creature (x1000)   e,h energy / health\n" ++
    "     rays [[dist x1000, type]] x7  (types: 0 food, 1 poison, 2 predator, 3 obstacle or wall)\n" ++
    "     food poison pred obst  [[x,y]...] (x1000)     pred = [x, y, mode]\n" ++
    "     acc brain-vs-expert (x1000)   share autopilot share (x1000)   ev [event codes]\n" ++
    "     tw  strongest learned synapses [[motor, neuron, weight*100], ...]\n" ++
    "   Every neuron is a real swarmrt process; a spike is a message. Nothing is simulated. */\n" ++
    "(function () {\n" ++
    "  var $ = function (id) { return document.getElementById(id); };\n" ++
    "  var ac = $('arena-cv'), bc = $('brain-cv'), cc = $('chart-cv'), apane = $('arena'), bpane = $('brain');\n" ++
    "  if (!ac) return;\n" ++
    "  var ag = ac.getContext('2d'), bg = bc.getContext('2d'), cg = cc.getContext('2d');\n" ++
    "  var dpr = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "  var AW = 0, AH = 0, BW = 0, BH = 0, N = 0, X = null, Y = null, act = null, dead = null;\n" ++
    "  var last = null, framesN = 0, fps = 0, fpsT = performance.now(), histT = 0, hist = [], shist = [];\n" ++
    "  var rings = [], tw = [], stats = {}, motorAct = [0, 0, 0, 0], logN = 0;\n" ++
    "  var TYPE_COL = [[80, 227, 194], [190, 110, 255], [255, 80, 80], [140, 150, 165]];\n" ++
    "  var MCOL = [[90, 200, 255], [255, 170, 90], [255, 120, 190], [245, 220, 80]];\n" ++
    "  var MNAME = ['forward', 'turn +', 'turn -', 'boost'];\n" ++
    "  var REGION = [{ name: 'visual', c: [80, 160, 255] }, { name: 'chemical', c: [80, 227, 194] }, { name: 'association', c: [190, 140, 255] }];\n" ++
    "  var geo = {}, arena = { s: 1, ox: 0, oy: 0 };\n" ++
    "\n" ++
    "  function fmt(n) { n = Math.round(n || 0); if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k'; return String(n); }\n" ++
    "  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }\n" ++
    "  function rgba(c, a) { return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }\n" ++
    "\n" ++
    "  /* ---------- sizing / layout ---------- */\n" ++
    "  function resize() {\n" ++
    "    AW = apane.clientWidth; AH = apane.clientHeight; BW = bpane.clientWidth; BH = bpane.clientHeight;\n" ++
    "    ac.width = AW * dpr; ac.height = AH * dpr; ac.style.width = AW + 'px'; ac.style.height = AH + 'px'; ag.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    bc.width = BW * dpr; bc.height = BH * dpr; bc.style.width = BW + 'px'; bc.style.height = BH + 'px'; bg.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    var cw = cc.clientWidth, ch = cc.clientHeight; cc.width = cw * dpr; cc.height = ch * dpr; cg.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    var side = Math.max(120, Math.min(AW - 24, AH - 78));\n" ++
    "    arena.s = side; arena.ox = (AW - side) / 2; arena.oy = 34;\n" ++
    "    place();\n" ++
    "  }\n" ++
    "  function place() {\n" ++
    "    var m = Math.min(BW, BH);\n" ++
    "    geo.reg = [\n" ++
    "      { cx: BW * 0.30, cy: BH * 0.27, r: m * 0.17 },\n" ++
    "      { cx: BW * 0.30, cy: BH * 0.73, r: m * 0.15 },\n" ++
    "      { cx: BW * 0.62, cy: BH * 0.50, r: m * 0.22 }\n" ++
    "    ];\n" ++
    "    geo.motor = []; for (var k = 0; k < 4; k++) geo.motor.push([BW - 56, BH * (0.2 + k * 0.2)]);\n" ++
    "    geo.retina = []; for (var q = 0; q < 7; q++) geo.retina.push([26, BH * 0.27 + (q - 3) * (m * 0.062)]);\n" ++
    "    geo.body = [26, BH * 0.73];\n" ++
    "    if (!N) return;\n" ++
    "    X = new Float32Array(N); Y = new Float32Array(N);\n" ++
    "    var per = N / 3;\n" ++
    "    for (var i = 0; i < N; i++) {\n" ++
    "      var r = Math.min(2, Math.floor(i / per)), li = i - r * per, R = geo.reg[r].r;\n" ++
    "      var rr = R * Math.sqrt((li + 0.5) / per), a = li * 2.399963;\n" ++
    "      X[i] = geo.reg[r].cx + rr * Math.cos(a); Y[i] = geo.reg[r].cy + rr * Math.sin(a);\n" ++
    "    }\n" ++
    "  }\n" ++
    "  if (window.ResizeObserver) { new ResizeObserver(resize).observe(apane); new ResizeObserver(resize).observe(bpane); } else window.addEventListener('resize', resize);\n" ++
    "  function setN(n) { N = n; act = new Float32Array(N); dead = new Uint8Array(N); tw = []; hist = []; shist = []; place(); }\n" ++
    "\n" ++
    "  /* ---------- frames ---------- */\n" ++
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  var EVTXT = { 1: ['Ate food', '80,227,194'], 2: ['Ate poison! health down', '190,110,255'], 3: ['Bitten by the predator', '255,90,90'], 4: ['Starved', '245,166,35'], 5: ['Slain by the predator', '255,90,90'], 6: ['Reborn', '90,160,255'] };\n" ++
    "  window.SwEvents.frame = function (d) {\n" ++
    "    var i, now = performance.now();\n" ++
    "    if (d.n !== N) setN(d.n);\n" ++
    "    for (i = 0; i < d.s.length; i++) act[d.s[i]] = 1;\n" ++
    "    for (i = 0; i < 4; i++) if (d.mo[i]) motorAct[i] = 1;\n" ++
    "    for (i = 0; i < d.ev.length; i++) {\n" ++
    "      var code = d.ev[i], pos = [d.x / 1000, d.y / 1000], col = (EVTXT[code] || [0, '255,255,255'])[1];\n" ++
    "      rings.push({ x: pos[0], y: pos[1], t: now, c: col, big: code >= 3 });\n" ++
    "      addLog(code, d);\n" ++
    "    }\n" ++
    "    if (d.tw && d.tw.length) tw = d.tw;\n" ++
    "    last = d; framesN++;\n" ++
    "    if (now - histT > 1000) { histT = now; hist.push(d.acc / 10); shist.push(d.share / 10); if (hist.length > 110) { hist.shift(); shist.shift(); } }\n" ++
    "    stat('procs', d.procs, fmtc, 'spawned in ' + fmtc(d.spms) + ' ms', 'up');\n" ++
    "    stat('sps', d.sps, fmt, (d.n ? (d.sps / 40 / d.n * 100).toFixed(1) : 0) + '% of neurons fire per tick', '');\n" ++
    "    stat('acc', d.acc / 10, function (x) { return x.toFixed(0) + '%'; }, d.auto ? 'autopilot drives ' + Math.round(d.share / 10) + '% of the time' : 'autopilot is OFF', d.share > 300 ? 'warn' : 'up');\n" ++
    "    stat('life', d.life / 40, function (x) { return x.toFixed(0) + 's'; }, 'best ' + Math.round(d.best / 40) + 's, ' + d.deaths + ' deaths', '');\n" ++
    "    stat('eat', d.eaten, fmtc, 'food eaten in total', 'up');\n" ++
    "    stat('hurt', d.poisoned + d.bitten, fmtc, d.poisoned + ' poison, ' + d.bitten + ' bites', d.poisoned + d.bitten ? 'bad' : '');\n" ++
    "    var e = $('b-e'), h = $('b-h'); if (e) e.style.width = Math.max(0, d.e) + '%'; if (h) h.style.width = Math.max(0, d.h) + '%';\n" ++
    "    var te = $('t-e'), th = $('t-h'); if (te) te.textContent = d.e; if (th) th.textContent = d.h;\n" ++
    "    var ah = $('ah'); if (ah) ah.innerHTML = d.dead ? '<b>' + (d.cause || 'dead') + '</b> &middot; respawning...' : '<b>the world</b> &middot; creature lives ' + Math.round(d.life / 40) + 's';\n" ++
    "    var bh = $('bh'); if (bh) bh.innerHTML = '<b>' + fmtc(N) + '</b> neurons &middot; three regions &middot; each spike is a message';\n" ++
    "    var sz = document.querySelectorAll('[data-size]'); for (i = 0; i < sz.length; i++) sz[i].classList.toggle('on', Number(sz[i].getAttribute('data-size')) === N);\n" ++
    "    tog('b-learn', 'Plasticity: ', d.learn); tog('b-auto', 'Autopilot: ', d.auto); tog('b-pred', 'Predator: ', d.pred_on);\n" ++
    "    var ha = $('h-acc'); if (ha) ha.textContent = (d.acc / 10).toFixed(0) + '% agree';\n" ++
    "    var hp = $('h-auto'); if (hp) hp.innerHTML = d.auto ? (d.share > 50 ? 'The <b>expert autopilot</b> is driving ' + Math.round(d.share / 10) + '% of the time. As the brain learns to copy it, this falls toward 0%.' : 'The <b>brain is driving</b> on its own.') : 'Autopilot is <b>off</b>: the brain drives alone.';\n" ++
    "  };\n" ++
    "  window.SwEvents.lesions = function (d) { for (var i = 0; i < d.l.length; i++) if (d.l[i] < N) dead[d.l[i]] = 1; };\n" ++
    "\n" ++
    "  function tog(id, label, on) { var b = $(id); if (b) { b.textContent = label + (on ? 'on' : 'off'); b.classList.toggle('on', !!on); } }\n" ++
    "  function addLog(code, d) {\n" ++
    "    var el = $('log'); if (!el) return; var t = EVTXT[code]; if (!t) return;\n" ++
    "    var row = document.createElement('div'); row.className = 'ev';\n" ++
    "    row.innerHTML = '<i style=\"background:rgb(' + t[1] + ')\"></i><span>' + t[0] + '</span><time>' + Math.round(d.life / 40) + 's</time>';\n" ++
    "    el.insertBefore(row, el.firstChild); while (el.children.length > 9) el.removeChild(el.lastChild);\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- animated counters ---------- */\n" ++
    "  function stat(id, v, f, sub, tone) {\n" ++
    "    var s = stats[id] || (stats[id] = { cur: v, tgt: v, shown: '' }); s.tgt = v; s.fmt = f;\n" ++
    "    var d = $('d-' + id); if (d) { d.textContent = sub; d.className = 'chip ' + (tone || ''); }\n" ++
    "  }\n" ++
    "  function tickStats() {\n" ++
    "    for (var id in stats) {\n" ++
    "      var s = stats[id]; s.cur += (s.tgt - s.cur) * 0.2; if (Math.abs(s.tgt - s.cur) < 0.3) s.cur = s.tgt;\n" ++
    "      var t = s.fmt(s.cur), el = $('v-' + id); if (el && t !== s.shown) { el.textContent = t; s.shown = t; }\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- controls ---------- */\n" ++
    "  document.addEventListener('click', function (e) {\n" ++
    "    var t = e.target.closest ? e.target.closest('[data-size],[data-lesion],#b-learn,#b-forget,#b-auto,#b-pred') : null;\n" ++
    "    if (!t) return;\n" ++
    "    if (t.hasAttribute('data-size')) { var bh = $('bh'); if (bh) bh.innerHTML = 'growing a new brain...'; window.swSend('size', { n: Number(t.getAttribute('data-size')) }); }\n" ++
    "    else if (t.hasAttribute('data-lesion')) window.swSend('lesion', { p: Number(t.getAttribute('data-lesion')) });\n" ++
    "    else if (t.id === 'b-learn') window.swSend('learn', {});\n" ++
    "    else if (t.id === 'b-forget') { hist = []; shist = []; window.swSend('forget', {}); }\n" ++
    "    else if (t.id === 'b-auto') window.swSend('auto', {});\n" ++
    "    else if (t.id === 'b-pred') window.swSend('pred', {});\n" ++
    "  });\n" ++
    "\n" ++
    "  /* ---------- draw: the world ---------- */\n" ++
    "  function ax(u) { return arena.ox + u * arena.s; }\n" ++
    "  function ay(u) { return arena.oy + u * arena.s; }\n" ++
    "  function drawArena(now) {\n" ++
    "    ag.clearRect(0, 0, AW, AH);\n" ++
    "    var S = arena.s;\n" ++
    "    ag.fillStyle = '#06070a'; ag.fillRect(arena.ox, arena.oy, S, S);\n" ++
    "    ag.strokeStyle = 'rgba(255,255,255,0.06)'; ag.lineWidth = 1;\n" ++
    "    for (var q = 0; q <= 8; q++) { ag.beginPath(); ag.moveTo(ax(q / 8), ay(0)); ag.lineTo(ax(q / 8), ay(1)); ag.moveTo(ax(0), ay(q / 8)); ag.lineTo(ax(1), ay(q / 8)); ag.stroke(); }\n" ++
    "    ag.strokeStyle = 'rgba(255,255,255,0.18)'; ag.strokeRect(arena.ox, arena.oy, S, S);\n" ++
    "    if (!last) return;\n" ++
    "    var d = last, i;\n" ++
    "    for (i = 0; i < d.obst.length; i++) { var o = d.obst[i]; ag.fillStyle = 'rgba(120,130,150,0.22)'; ag.strokeStyle = 'rgba(160,170,190,0.45)'; ag.beginPath(); ag.arc(ax(o[0] / 1000), ay(o[1] / 1000), o[2] / 1000 * S, 0, 6.2832); ag.fill(); ag.stroke(); }\n" ++
    "    var pulse = 0.5 + 0.5 * Math.sin(now / 260);\n" ++
    "    for (i = 0; i < d.food.length; i++) {\n" ++
    "      var f = d.food[i], fx = ax(f[0] / 1000), fy = ay(f[1] / 1000);\n" ++
    "      ag.fillStyle = 'rgba(80,227,194,' + (0.12 + pulse * 0.1) + ')'; ag.beginPath(); ag.arc(fx, fy, S * 0.03, 0, 6.2832); ag.fill();\n" ++
    "      ag.fillStyle = '#50e3c2'; ag.beginPath(); ag.arc(fx, fy, S * 0.012, 0, 6.2832); ag.fill();\n" ++
    "    }\n" ++
    "    for (i = 0; i < d.poison.length; i++) {\n" ++
    "      var p = d.poison[i], px = ax(p[0] / 1000), py = ay(p[1] / 1000);\n" ++
    "      ag.fillStyle = 'rgba(190,110,255,' + (0.14 + pulse * 0.1) + ')'; ag.beginPath(); ag.arc(px, py, S * 0.035, 0, 6.2832); ag.fill();\n" ++
    "      ag.strokeStyle = '#be6eff'; ag.lineWidth = 1.5; ag.beginPath(); ag.arc(px, py, S * 0.014, 0, 6.2832); ag.stroke();\n" ++
    "      ag.beginPath(); ag.moveTo(px - S * 0.008, py - S * 0.008); ag.lineTo(px + S * 0.008, py + S * 0.008); ag.moveTo(px + S * 0.008, py - S * 0.008); ag.lineTo(px - S * 0.008, py + S * 0.008); ag.stroke();\n" ++
    "    }\n" ++
    "    /* predator */\n" ++
    "    if (d.pred_on) {\n" ++
    "      var pr = d.pred, qx = ax(pr[0] / 1000), qy = ay(pr[1] / 1000), mode = pr[2];\n" ++
    "      var pc = mode === 1 ? [255, 70, 70] : mode === 2 ? [140, 80, 80] : [255, 150, 90];\n" ++
    "      var gr = ag.createRadialGradient(qx, qy, 0, qx, qy, S * (mode === 1 ? 0.09 : 0.06));\n" ++
    "      gr.addColorStop(0, rgba(pc, mode === 1 ? 0.5 : 0.25)); gr.addColorStop(1, rgba(pc, 0));\n" ++
    "      ag.fillStyle = gr; ag.fillRect(qx - S * 0.1, qy - S * 0.1, S * 0.2, S * 0.2);\n" ++
    "      ag.fillStyle = rgba(pc, 1); ag.beginPath(); ag.arc(qx, qy, S * 0.02, 0, 6.2832); ag.fill();\n" ++
    "      ag.fillStyle = '#fff'; ag.beginPath(); ag.arc(qx - S * 0.006, qy - S * 0.004, 1.6, 0, 6.2832); ag.arc(qx + S * 0.006, qy - S * 0.004, 1.6, 0, 6.2832); ag.fill();\n" ++
    "      ag.fillStyle = 'rgba(255,255,255,0.5)'; ag.font = '10px ui-sans-serif,-apple-system,sans-serif'; ag.textAlign = 'center';\n" ++
    "      ag.fillText(mode === 1 ? 'hunting' : mode === 2 ? 'resting' : 'prowling', qx, qy - S * 0.035);\n" ++
    "    }\n" ++
    "    var cx = ax(d.x / 1000), cy = ay(d.y / 1000), hx = d.hx / 1000, hy = d.hy / 1000;\n" ++
    "    if (!d.dead) {\n" ++
    "      /* the 7 vision rays */\n" ++
    "      var cs = [[0.5, -0.866], [0.766, -0.643], [0.94, -0.342], [1, 0], [0.94, 0.342], [0.766, 0.643], [0.5, 0.866]];\n" ++
    "      for (i = 0; i < 7; i++) {\n" ++
    "        var rdx = hx * cs[i][0] - hy * cs[i][1], rdy = hx * cs[i][1] + hy * cs[i][0], dist = Math.min(0.45, d.rays[i][0] / 1000), hit = d.rays[i][0] / 1000 <= 0.45;\n" ++
    "        var col = TYPE_COL[d.rays[i][1]];\n" ++
    "        ag.strokeStyle = rgba(col, hit ? 0.55 : 0.1); ag.lineWidth = hit ? 1.3 : 0.7;\n" ++
    "        ag.beginPath(); ag.moveTo(cx, cy); ag.lineTo(cx + rdx * dist * S, cy + rdy * dist * S); ag.stroke();\n" ++
    "        if (hit) { ag.fillStyle = rgba(col, 0.9); ag.beginPath(); ag.arc(cx + rdx * dist * S, cy + rdy * dist * S, 3, 0, 6.2832); ag.fill(); }\n" ++
    "      }\n" ++
    "      /* body */\n" ++
    "      var hurt = d.ev.indexOf(2) >= 0 || d.ev.indexOf(3) >= 0;\n" ++
    "      var g2 = ag.createRadialGradient(cx, cy, 0, cx, cy, S * 0.05);\n" ++
    "      g2.addColorStop(0, 'rgba(120,210,255,0.5)'); g2.addColorStop(1, 'rgba(120,210,255,0)');\n" ++
    "      ag.fillStyle = g2; ag.fillRect(cx - S * 0.05, cy - S * 0.05, S * 0.1, S * 0.1);\n" ++
    "      ag.fillStyle = hurt ? '#ff8a8a' : '#e6fbff'; ag.beginPath(); ag.arc(cx, cy, S * 0.017, 0, 6.2832); ag.fill();\n" ++
    "      ag.strokeStyle = '#fff'; ag.lineWidth = 2; ag.beginPath(); ag.moveTo(cx, cy); ag.lineTo(cx + hx * S * 0.03, cy + hy * S * 0.03); ag.stroke();\n" ++
    "    } else {\n" ++
    "      ag.strokeStyle = 'rgba(255,90,90,0.8)'; ag.lineWidth = 2; ag.beginPath();\n" ++
    "      ag.moveTo(cx - 8, cy - 8); ag.lineTo(cx + 8, cy + 8); ag.moveTo(cx + 8, cy - 8); ag.lineTo(cx - 8, cy + 8); ag.stroke();\n" ++
    "    }\n" ++
    "    for (i = rings.length - 1; i >= 0; i--) {\n" ++
    "      var r = rings[i], t = (now - r.t) / 700;\n" ++
    "      if (t >= 1) { rings.splice(i, 1); continue; }\n" ++
    "      ag.strokeStyle = 'rgba(' + r.c + ',' + (1 - t) + ')'; ag.lineWidth = 2;\n" ++
    "      ag.beginPath(); ag.arc(ax(r.x), ay(r.y), S * (0.02 + (r.big ? 0.09 : 0.05) * t), 0, 6.2832); ag.stroke();\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- draw: the brain ---------- */\n" ++
    "  function drawBrain(now) {\n" ++
    "    bg.clearRect(0, 0, BW, BH);\n" ++
    "    if (!N || !X) return;\n" ++
    "    var i, r, m, k;\n" ++
    "    for (r = 0; r < 3; r++) {\n" ++
    "      var rg = geo.reg[r];\n" ++
    "      bg.strokeStyle = rgba(REGION[r].c, 0.18); bg.lineWidth = 1; bg.beginPath(); bg.arc(rg.cx, rg.cy, rg.r + 8, 0, 6.2832); bg.stroke();\n" ++
    "      bg.fillStyle = rgba(REGION[r].c, 0.85); bg.font = '500 11px ui-sans-serif,-apple-system,sans-serif'; bg.textAlign = 'center';\n" ++
    "      bg.fillText(REGION[r].name, rg.cx, rg.cy - rg.r - 14);\n" ++
    "    }\n" ++
    "    var per = N / 3;\n" ++
    "    for (i = 0; i < N; i++) {\n" ++
    "      var reg = Math.min(2, Math.floor(i / per));\n" ++
    "      if (dead[i]) { bg.fillStyle = 'rgba(70,40,40,0.55)'; bg.fillRect(X[i] - 1, Y[i] - 1, 2, 2); continue; }\n" ++
    "      bg.fillStyle = rgba(REGION[reg].c, 0.22); bg.fillRect(X[i] - 0.8, Y[i] - 0.8, 1.6, 1.6);\n" ++
    "      if (act[i] > 0.04) act[i] *= 0.86; else act[i] = 0;\n" ++
    "    }\n" ++
    "    bg.globalCompositeOperation = 'lighter';\n" ++
    "    for (i = 0; i < N; i++) {\n" ++
    "      var b = act[i];\n" ++
    "      if (b > 0.05) {\n" ++
    "        var c = REGION[Math.min(2, Math.floor(i / per))].c;\n" ++
    "        bg.fillStyle = rgba([Math.min(255, c[0] + 90), Math.min(255, c[1] + 70), 255], b * 0.9);\n" ++
    "        bg.beginPath(); bg.arc(X[i], Y[i], 1.1 + b * 2.4, 0, 6.2832); bg.fill();\n" ++
    "      }\n" ++
    "    }\n" ++
    "    for (k = 0; k < tw.length; k++) {\n" ++
    "      var q = tw[k], mm = q[0], ni = q[1], w = q[2] / 100;\n" ++
    "      if (ni >= N) continue;\n" ++
    "      var m1 = geo.motor[mm], cxm = (X[ni] + m1[0]) / 2, cym = (Y[ni] + m1[1]) / 2 - 14;\n" ++
    "      bg.strokeStyle = rgba(MCOL[mm], Math.min(0.5, 0.05 + w * 0.25 + act[ni] * 0.5)); bg.lineWidth = 0.6 + w * 0.4;\n" ++
    "      bg.beginPath(); bg.moveTo(X[ni], Y[ni]); bg.quadraticCurveTo(cxm, cym, m1[0], m1[1]); bg.stroke();\n" ++
    "    }\n" ++
    "    bg.globalCompositeOperation = 'source-over';\n" ++
    "    /* retina: what each vision ray currently sees */\n" ++
    "    if (last) {\n" ++
    "      bg.font = '10px ui-sans-serif,-apple-system,sans-serif'; bg.textAlign = 'left'; bg.fillStyle = '#6b6b6b';\n" ++
    "      bg.fillText('retina', 12, geo.retina[0][1] - 20);\n" ++
    "      for (i = 0; i < 7; i++) {\n" ++
    "        var ry = last.rays[i], hitp = ry[0] / 1000 <= 0.45, cc2 = TYPE_COL[ry[1]], rp = geo.retina[i];\n" ++
    "        var a2 = hitp ? 0.35 + 0.65 * (1 - ry[0] / 450) : 0.12;\n" ++
    "        bg.fillStyle = rgba(cc2, a2); bg.fillRect(rp[0] - 8, rp[1] - 6, 16, 12);\n" ++
    "        if (hitp) { bg.strokeStyle = rgba(cc2, 0.12); bg.lineWidth = 1; for (k = 0; k < 6; k++) { var tn = (i * 211 + k * 313) % Math.floor(per); bg.beginPath(); bg.moveTo(rp[0] + 8, rp[1]); bg.lineTo(X[tn], Y[tn]); bg.stroke(); } }\n" ++
    "      }\n" ++
    "      /* body sense: hunger, health, pain */\n" ++
    "      bg.fillStyle = '#6b6b6b'; bg.fillText('body', 12, geo.body[1] - 26);\n" ++
    "      var bars = [['E', last.e / 100, [80, 227, 194]], ['H', last.h / 100, [255, 107, 107]]];\n" ++
    "      for (i = 0; i < 2; i++) { bg.fillStyle = 'rgba(255,255,255,0.08)'; bg.fillRect(12, geo.body[1] - 14 + i * 14, 28, 6); bg.fillStyle = rgba(bars[i][2], 0.9); bg.fillRect(12, geo.body[1] - 14 + i * 14, 28 * bars[i][1], 6); }\n" ++
    "    }\n" ++
    "    /* motor neurons, brain vs expert */\n" ++
    "    for (m = 0; m < 4; m++) {\n" ++
    "      var mp = geo.motor[m], ma = motorAct[m]; motorAct[m] = ma * 0.9;\n" ++
    "      var rr = 11 + ma * 5;\n" ++
    "      var g3 = bg.createRadialGradient(mp[0], mp[1], 0, mp[0], mp[1], rr * 3);\n" ++
    "      g3.addColorStop(0, rgba(MCOL[m], 0.15 + ma * 0.5)); g3.addColorStop(1, rgba(MCOL[m], 0));\n" ++
    "      bg.fillStyle = g3; bg.fillRect(mp[0] - rr * 3, mp[1] - rr * 3, rr * 6, rr * 6);\n" ++
    "      bg.fillStyle = rgba(MCOL[m], 0.75 + ma * 0.25); bg.beginPath(); bg.arc(mp[0], mp[1], rr, 0, 6.2832); bg.fill();\n" ++
    "      bg.fillStyle = '#ededed'; bg.textAlign = 'right'; bg.font = '500 10.5px ui-sans-serif,-apple-system,sans-serif';\n" ++
    "      bg.fillText(MNAME[m], mp[0] - rr - 8, mp[1] + 4);\n" ++
    "      if (last) {\n" ++
    "        var agree = !!last.mo[m] === !!last.ex[m];\n" ++
    "        bg.strokeStyle = last.ex[m] ? '#50e3c2' : 'rgba(255,255,255,0.25)'; bg.lineWidth = 1.5; bg.beginPath(); bg.arc(mp[0], mp[1] + rr + 9, 3.5, 0, 6.2832); bg.stroke();\n" ++
    "        bg.fillStyle = agree ? 'rgba(80,227,194,0.9)' : 'rgba(255,90,90,0.9)'; bg.beginPath(); bg.arc(mp[0], mp[1] + rr + 9, 1.8, 0, 6.2832); bg.fill();\n" ++
    "      }\n" ++
    "    }\n" ++
    "    bg.fillStyle = '#6b6b6b'; bg.textAlign = 'right'; bg.font = '10px ui-sans-serif,-apple-system,sans-serif';\n" ++
    "    bg.fillText('ring = expert says go, dot = agrees', BW - 14, BH - 14);\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- draw: learning curve ---------- */\n" ++
    "  function drawChart() {\n" ++
    "    var w = cc.clientWidth, h = cc.clientHeight; cg.clearRect(0, 0, w, h);\n" ++
    "    cg.strokeStyle = 'rgba(255,255,255,0.06)'; cg.lineWidth = 1;\n" ++
    "    for (var q = 0; q <= 4; q++) { var y = 4 + q * (h - 8) / 4; cg.beginPath(); cg.moveTo(0, y); cg.lineTo(w, y); cg.stroke(); }\n" ++
    "    function line(arr, col, fill) {\n" ++
    "      if (arr.length < 2) return;\n" ++
    "      function X1(i) { return i / 109 * w; } function Y1(v) { return h - 4 - (v / 100) * (h - 8); }\n" ++
    "      if (fill) { var gr = cg.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, rgba(col, 0.25)); gr.addColorStop(1, rgba(col, 0)); cg.beginPath(); cg.moveTo(X1(0), h); for (var i = 0; i < arr.length; i++) cg.lineTo(X1(i), Y1(arr[i])); cg.lineTo(X1(arr.length - 1), h); cg.closePath(); cg.fillStyle = gr; cg.fill(); }\n" ++
    "      cg.beginPath(); for (var j = 0; j < arr.length; j++) { if (j === 0) cg.moveTo(X1(j), Y1(arr[j])); else cg.lineTo(X1(j), Y1(arr[j])); }\n" ++
    "      cg.strokeStyle = rgba(col, 0.95); cg.lineWidth = 1.5; cg.stroke();\n" ++
    "    }\n" ++
    "    line(hist, [80, 227, 194], true); line(shist, [245, 166, 35], false);\n" ++
    "  }\n" ++
    "\n" ++
    "  function frame(now) {\n" ++
    "    requestAnimationFrame(frame);\n" ++
    "    if (now - fpsT > 1000) { fps = framesN; framesN = 0; fpsT = now; var f = $('o-fps'); if (f) f.textContent = fps; }\n" ++
    "    tickStats();\n" ++
    "    if (!AW) { resize(); return; }\n" ++
    "    drawArena(now); drawBrain(now); drawChart();\n" ++
    "  }\n" ++
    "  window.__swCreature = { get N() { return N; }, get last() { return last; } };\n" ++
    "  resize();\n" ++
    "  requestAnimationFrame(frame);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
