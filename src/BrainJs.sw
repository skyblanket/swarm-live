module BrainJs

# GENERATED from src/brain.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() {
    "/* Neuron Swarm - client. Source of truth for src/BrainJs.sw\n" ++
    "   (python3 scripts/embed_js.py src/brain.js BrainJs src/BrainJs.sw).\n" ++
    "\n" ++
    "   One frame per 25 ms tick:\n" ++
    "     n neurons         s  [ids of reservoir neurons that spiked this tick]\n" ++
    "     mo [4 motor flags: right, left, down, up]      sn  which sensor is active (octant*3 + distance bin)\n" ++
    "     c [x,y] creature  f  [x,y] food  (x1000)       eaten  acc (x1000)  procs  sps  eps  learn  lz  spms\n" ++
    "     tw [[motor, neuron, weight*100], ...] strongest learned synapses (about once a second)\n" ++
    "   Every neuron is a real swarmrt process; a spike is a message. Nothing is simulated. */\n" ++
    "(function () {\n" ++
    "  var $ = function (id) { return document.getElementById(id); };\n" ++
    "  var bc = $('brain-cv'), ac = $('arena-cv'), cc = $('chart-cv'), box = $('brain');\n" ++
    "  if (!bc) return;\n" ++
    "  var g = bc.getContext('2d'), ag = ac.getContext('2d'), cg = cc.getContext('2d');\n" ++
    "  var dpr = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "  var W = 0, H = 0, N = 0, X = null, Y = null, act = null, dead = null;\n" ++
    "  var motorAct = [0, 0, 0, 0], sensorAct = new Float32Array(24), tw = [];\n" ++
    "  var cre = { x: 0.5, y: 0.5 }, food = { x: 0.8, y: 0.3 }, trail = [], eatRings = [], lastEaten = 0;\n" ++
    "  var hist = [], last = null, framesN = 0, fps = 0, fpsT = performance.now(), histT = 0;\n" ++
    "  var stats = {}, layout = { cx: 0, cy: 0, R: 0 }, sensorPos = [], motorPos = [];\n" ++
    "  var MCOL = [[255, 120, 90], [90, 200, 255], [190, 140, 255], [245, 200, 70]];\n" ++
    "  var MNAME = ['right', 'left', 'down', 'up'];\n" ++
    "\n" ++
    "  function fmt(n) { n = Math.round(n || 0); if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k'; return String(n); }\n" ++
    "  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }\n" ++
    "  function rgba(c, a) { return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }\n" ++
    "\n" ++
    "  /* ---------- sizing / layout ---------- */\n" ++
    "  function resize() {\n" ++
    "    W = box.clientWidth; H = box.clientHeight;\n" ++
    "    bc.width = W * dpr; bc.height = H * dpr; bc.style.width = W + 'px'; bc.style.height = H + 'px';\n" ++
    "    g.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    var aw = ac.clientWidth; ac.width = aw * dpr; ac.height = aw * dpr; ag.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    var cw = cc.clientWidth, ch = cc.clientHeight; cc.width = cw * dpr; cc.height = ch * dpr; cg.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    place();\n" ++
    "  }\n" ++
    "  function place() {\n" ++
    "    layout.R = Math.max(80, Math.min(W * 0.33, H * 0.42));\n" ++
    "    layout.cx = W * 0.5; layout.cy = H * 0.52;\n" ++
    "    X = new Float32Array(N); Y = new Float32Array(N);\n" ++
    "    for (var i = 0; i < N; i++) {\n" ++
    "      var r = layout.R * Math.sqrt((i + 0.5) / N), a = i * 2.399963;\n" ++
    "      X[i] = layout.cx + r * Math.cos(a); Y[i] = layout.cy + r * Math.sin(a);\n" ++
    "    }\n" ++
    "    sensorPos = [];\n" ++
    "    for (var s = 0; s < 24; s++) {\n" ++
    "      var oct = Math.floor(s / 3), bin = s % 3;\n" ++
    "      var ang = (oct / 8) * 6.2832 - 1.2, rr = layout.R + 70 + bin * 16;\n" ++
    "      sensorPos.push([layout.cx - layout.R * 0.0 - Math.cos(ang) * 0 - (layout.R + 62 + bin * 18), layout.cy + (oct - 3.5) * (layout.R * 0.2)]);\n" ++
    "    }\n" ++
    "    motorPos = [];\n" ++
    "    for (var m = 0; m < 4; m++) motorPos.push([layout.cx + layout.R + 90, layout.cy + (m - 1.5) * (layout.R * 0.42)]);\n" ++
    "  }\n" ++
    "  if (window.ResizeObserver) new ResizeObserver(resize).observe(box); else window.addEventListener('resize', resize);\n" ++
    "  function setN(n) {\n" ++
    "    N = n; act = new Float32Array(N); dead = new Uint8Array(N); tw = []; hist = []; trail = [];\n" ++
    "    place();\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- frames ---------- */\n" ++
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  window.SwEvents.frame = function (d) {\n" ++
    "    var i;\n" ++
    "    if (d.n !== N) setN(d.n);\n" ++
    "    for (i = 0; i < d.s.length; i++) act[d.s[i]] = 1;\n" ++
    "    for (i = 0; i < 4; i++) if (d.mo[i]) motorAct[i] = 1;\n" ++
    "    for (i = 0; i < 24; i++) sensorAct[i] *= 0.8;\n" ++
    "    sensorAct[d.sn] = 1;\n" ++
    "    cre.x = d.c[0] / 1000; cre.y = d.c[1] / 1000; food.x = d.f[0] / 1000; food.y = d.f[1] / 1000;\n" ++
    "    trail.push([cre.x, cre.y]); if (trail.length > 70) trail.shift();\n" ++
    "    if (d.eaten > lastEaten) { eatRings.push({ x: food.x, y: food.y, t: performance.now() }); }\n" ++
    "    lastEaten = d.eaten;\n" ++
    "    if (d.tw && d.tw.length) tw = d.tw;\n" ++
    "    last = d; framesN++;\n" ++
    "    var now = performance.now();\n" ++
    "    if (now - histT > 1000) { histT = now; hist.push(d.acc / 10); if (hist.length > 110) hist.shift(); }\n" ++
    "    stat('procs', d.procs, fmtc, 'spawned in ' + fmtc(d.spms) + ' ms', 'up');\n" ++
    "    stat('sps', d.sps, fmt, (d.n ? (d.sps / 40 / d.n * 100).toFixed(1) : 0) + '% of neurons fire per tick', '');\n" ++
    "    stat('eps', d.eps, fmt, 'each spike is ~12 messages', '');\n" ++
    "    stat('acc', d.acc / 10, function (x) { return x.toFixed(0) + '%'; }, d.learn ? 'learning is on' : 'learning is frozen', d.learn ? 'up' : '');\n" ++
    "    stat('eat', d.eaten, fmtc, d.lz ? fmtc(d.lz) + ' neurons lesioned' : 'no brain damage', d.lz ? 'bad' : '');\n" ++
    "    var bh = $('bh'); if (bh) bh.innerHTML = '<b>' + fmtc(N) + '</b> neurons &middot; each spike is a message between processes';\n" ++
    "    var sz = document.querySelectorAll('[data-size]');\n" ++
    "    for (i = 0; i < sz.length; i++) sz[i].classList.toggle('on', Number(sz[i].getAttribute('data-size')) === N);\n" ++
    "    var lb = $('b-learn'); if (lb) { lb.textContent = 'Learning: ' + (d.learn ? 'on' : 'off'); lb.classList.toggle('on', !!d.learn); }\n" ++
    "    var ha = $('h-acc'); if (ha) ha.textContent = 'accuracy ' + (d.acc / 10).toFixed(0) + '%';\n" ++
    "  };\n" ++
    "  window.SwEvents.lesions = function (d) {\n" ++
    "    for (var i = 0; i < d.l.length; i++) if (d.l[i] < N) dead[d.l[i]] = 1;\n" ++
    "  };\n" ++
    "\n" ++
    "  /* ---------- animated counters ---------- */\n" ++
    "  function stat(id, v, f, sub, tone) {\n" ++
    "    var s = stats[id] || (stats[id] = { cur: v, tgt: v, shown: '' });\n" ++
    "    s.tgt = v; s.fmt = f;\n" ++
    "    var d = $('d-' + id); if (d) { d.textContent = sub; d.className = 'chip ' + (tone || ''); }\n" ++
    "  }\n" ++
    "  function tickStats() {\n" ++
    "    for (var id in stats) {\n" ++
    "      var s = stats[id]; s.cur += (s.tgt - s.cur) * 0.2; if (Math.abs(s.tgt - s.cur) < 0.3) s.cur = s.tgt;\n" ++
    "      var t = s.fmt(s.cur), el = $('v-' + id);\n" ++
    "      if (el && t !== s.shown) { el.textContent = t; s.shown = t; }\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- controls ---------- */\n" ++
    "  document.addEventListener('click', function (e) {\n" ++
    "    var t = e.target.closest ? e.target.closest('[data-size],[data-lesion],#b-learn,#b-forget') : null;\n" ++
    "    if (!t) return;\n" ++
    "    if (t.hasAttribute('data-size')) { var bh = $('bh'); if (bh) bh.innerHTML = 'growing a new brain...'; window.swSend('size', { n: Number(t.getAttribute('data-size')) }); }\n" ++
    "    else if (t.hasAttribute('data-lesion')) window.swSend('lesion', { p: Number(t.getAttribute('data-lesion')) });\n" ++
    "    else if (t.id === 'b-learn') window.swSend('learn', {});\n" ++
    "    else if (t.id === 'b-forget') { hist = []; window.swSend('forget', {}); }\n" ++
    "  });\n" ++
    "  ac.addEventListener('mousedown', function (e) {\n" ++
    "    var r = ac.getBoundingClientRect();\n" ++
    "    window.swSend('food', { x: Math.round((e.clientX - r.left) / r.width * 1000), y: Math.round((e.clientY - r.top) / r.height * 1000) });\n" ++
    "  });\n" ++
    "\n" ++
    "  /* ---------- draw: the brain ---------- */\n" ++
    "  function drawBrain(now) {\n" ++
    "    g.clearRect(0, 0, W, H);\n" ++
    "    if (!N || !X) return;\n" ++
    "    var i, m, s;\n" ++
    "    /* faint disc */\n" ++
    "    g.strokeStyle = 'rgba(255,255,255,0.05)'; g.lineWidth = 1;\n" ++
    "    g.beginPath(); g.arc(layout.cx, layout.cy, layout.R + 12, 0, 6.2832); g.stroke();\n" ++
    "    /* neurons */\n" ++
    "    for (i = 0; i < N; i++) {\n" ++
    "      var a = act[i];\n" ++
    "      if (dead[i]) { g.fillStyle = 'rgba(70,40,40,0.55)'; g.fillRect(X[i] - 1, Y[i] - 1, 2, 2); continue; }\n" ++
    "      g.fillStyle = 'rgba(90,110,145,0.30)'; g.fillRect(X[i] - 0.9, Y[i] - 0.9, 1.8, 1.8);\n" ++
    "      if (a > 0.04) act[i] = a * 0.86; else act[i] = 0;\n" ++
    "    }\n" ++
    "    g.globalCompositeOperation = 'lighter';\n" ++
    "    for (i = 0; i < N; i++) {\n" ++
    "      var b = act[i];\n" ++
    "      if (b > 0.05) {\n" ++
    "        g.fillStyle = 'rgba(210,240,255,' + b * 0.9 + ')';\n" ++
    "        g.beginPath(); g.arc(X[i], Y[i], 1.2 + b * 2.6, 0, 6.2832); g.fill();\n" ++
    "        if (b > 0.7) { g.fillStyle = 'rgba(120,200,255,' + (b - 0.7) * 0.5 + ')'; g.beginPath(); g.arc(X[i], Y[i], 7, 0, 6.2832); g.fill(); }\n" ++
    "      }\n" ++
    "    }\n" ++
    "    /* learned synapses: strongest weights into each motor neuron */\n" ++
    "    for (var k = 0; k < tw.length; k++) {\n" ++
    "      var q = tw[k], mm = q[0], ni = q[1], w = q[2] / 100;\n" ++
    "      if (ni >= N || !motorPos[mm]) continue;\n" ++
    "      var p0 = [X[ni], Y[ni]], p1 = motorPos[mm], cxm = (p0[0] + p1[0]) / 2, cym = (p0[1] + p1[1]) / 2 - 22;\n" ++
    "      var al = Math.min(0.55, 0.05 + w * 0.28 + act[ni] * 0.5);\n" ++
    "      g.strokeStyle = rgba(MCOL[mm], al); g.lineWidth = 0.6 + w * 0.5;\n" ++
    "      g.beginPath(); g.moveTo(p0[0], p0[1]); g.quadraticCurveTo(cxm, cym, p1[0], p1[1]); g.stroke();\n" ++
    "    }\n" ++
    "    g.globalCompositeOperation = 'source-over';\n" ++
    "    /* sensors */\n" ++
    "    g.font = '10px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'right';\n" ++
    "    for (s = 0; s < 24; s++) {\n" ++
    "      var sp = sensorPos[s], sa = sensorAct[s]; sensorAct[s] = sa * 0.97;\n" ++
    "      g.fillStyle = sa > 0.1 ? 'rgba(59,158,255,' + (0.4 + sa * 0.6) + ')' : 'rgba(59,158,255,0.25)';\n" ++
    "      g.beginPath(); g.arc(sp[0], sp[1], 3 + sa * 3, 0, 6.2832); g.fill();\n" ++
    "      if (sa > 0.3) {\n" ++
    "        g.strokeStyle = 'rgba(59,158,255,' + sa * 0.25 + ')'; g.lineWidth = 1;\n" ++
    "        for (var j = 0; j < 14; j++) { var tn = (s * 131 + j * 977) % N; g.beginPath(); g.moveTo(sp[0], sp[1]); g.lineTo(X[tn], Y[tn]); g.stroke(); }\n" ++
    "      }\n" ++
    "    }\n" ++
    "    g.fillStyle = '#6b6b6b'; g.textAlign = 'center'; g.fillText('sensors: where the food is', layout.cx - layout.R - 62, layout.cy - layout.R * 0.0 - (layout.R * 0.2) * 4.6);\n" ++
    "    /* motor neurons */\n" ++
    "    for (m = 0; m < 4; m++) {\n" ++
    "      var mp = motorPos[m], ma = motorAct[m]; motorAct[m] = ma * 0.9;\n" ++
    "      var rr = 12 + ma * 6;\n" ++
    "      var gr = g.createRadialGradient(mp[0], mp[1], 0, mp[0], mp[1], rr * 3);\n" ++
    "      gr.addColorStop(0, rgba(MCOL[m], 0.15 + ma * 0.5)); gr.addColorStop(1, rgba(MCOL[m], 0));\n" ++
    "      g.fillStyle = gr; g.fillRect(mp[0] - rr * 3, mp[1] - rr * 3, rr * 6, rr * 6);\n" ++
    "      g.fillStyle = rgba(MCOL[m], 0.75 + ma * 0.25); g.beginPath(); g.arc(mp[0], mp[1], rr, 0, 6.2832); g.fill();\n" ++
    "      g.fillStyle = '#ededed'; g.textAlign = 'left'; g.font = '500 11px ui-sans-serif,-apple-system,sans-serif';\n" ++
    "      g.fillText(MNAME[m], mp[0] + rr + 8, mp[1] + 4);\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- draw: the creature ---------- */\n" ++
    "  function drawArena(now) {\n" ++
    "    var w = ac.clientWidth;\n" ++
    "    ag.clearRect(0, 0, w, w);\n" ++
    "    ag.strokeStyle = 'rgba(255,255,255,0.05)'; ag.lineWidth = 1;\n" ++
    "    for (var q = 1; q < 4; q++) { ag.beginPath(); ag.moveTo(q * w / 4, 0); ag.lineTo(q * w / 4, w); ag.moveTo(0, q * w / 4); ag.lineTo(w, q * w / 4); ag.stroke(); }\n" ++
    "    for (var i = 1; i < trail.length; i++) {\n" ++
    "      ag.strokeStyle = 'rgba(90,200,255,' + (i / trail.length) * 0.45 + ')'; ag.lineWidth = 1 + (i / trail.length) * 2;\n" ++
    "      ag.beginPath(); ag.moveTo(trail[i - 1][0] * w, trail[i - 1][1] * w); ag.lineTo(trail[i][0] * w, trail[i][1] * w); ag.stroke();\n" ++
    "    }\n" ++
    "    /* teacher line */\n" ++
    "    ag.setLineDash([3, 5]); ag.strokeStyle = 'rgba(80,227,194,0.25)';\n" ++
    "    ag.beginPath(); ag.moveTo(cre.x * w, cre.y * w); ag.lineTo(food.x * w, food.y * w); ag.stroke(); ag.setLineDash([]);\n" ++
    "    var pulse = 0.5 + 0.5 * Math.sin(now / 250);\n" ++
    "    ag.fillStyle = 'rgba(80,227,194,' + (0.15 + pulse * 0.15) + ')'; ag.beginPath(); ag.arc(food.x * w, food.y * w, 13 + pulse * 3, 0, 6.2832); ag.fill();\n" ++
    "    ag.fillStyle = '#50e3c2'; ag.beginPath(); ag.arc(food.x * w, food.y * w, 5, 0, 6.2832); ag.fill();\n" ++
    "    for (var e = eatRings.length - 1; e >= 0; e--) {\n" ++
    "      var er = eatRings[e], t = (now - er.t) / 700;\n" ++
    "      if (t >= 1) { eatRings.splice(e, 1); continue; }\n" ++
    "      ag.strokeStyle = 'rgba(80,227,194,' + (1 - t) + ')'; ag.lineWidth = 2;\n" ++
    "      ag.beginPath(); ag.arc(er.x * w, er.y * w, 6 + 34 * t, 0, 6.2832); ag.stroke();\n" ++
    "    }\n" ++
    "    var gr = ag.createRadialGradient(cre.x * w, cre.y * w, 0, cre.x * w, cre.y * w, 22);\n" ++
    "    gr.addColorStop(0, 'rgba(120,210,255,0.55)'); gr.addColorStop(1, 'rgba(120,210,255,0)');\n" ++
    "    ag.fillStyle = gr; ag.fillRect(cre.x * w - 22, cre.y * w - 22, 44, 44);\n" ++
    "    ag.fillStyle = '#e6fbff'; ag.beginPath(); ag.arc(cre.x * w, cre.y * w, 5, 0, 6.2832); ag.fill();\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- draw: the learning curve ---------- */\n" ++
    "  function drawChart() {\n" ++
    "    var w = cc.clientWidth, h = cc.clientHeight;\n" ++
    "    cg.clearRect(0, 0, w, h);\n" ++
    "    cg.strokeStyle = 'rgba(255,255,255,0.06)'; cg.lineWidth = 1;\n" ++
    "    for (var q = 0; q <= 4; q++) { var y = 4 + q * (h - 8) / 4; cg.beginPath(); cg.moveTo(0, y); cg.lineTo(w, y); cg.stroke(); }\n" ++
    "    if (hist.length < 2) return;\n" ++
    "    function X1(i) { return i / 109 * w; }\n" ++
    "    function Y1(v) { return h - 4 - (v / 100) * (h - 8); }\n" ++
    "    var gr = cg.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, 'rgba(80,227,194,0.28)'); gr.addColorStop(1, 'rgba(80,227,194,0)');\n" ++
    "    cg.beginPath(); cg.moveTo(X1(0), h);\n" ++
    "    for (var i = 0; i < hist.length; i++) cg.lineTo(X1(i), Y1(hist[i]));\n" ++
    "    cg.lineTo(X1(hist.length - 1), h); cg.closePath(); cg.fillStyle = gr; cg.fill();\n" ++
    "    cg.beginPath(); for (var j = 0; j < hist.length; j++) { if (j === 0) cg.moveTo(X1(j), Y1(hist[j])); else cg.lineTo(X1(j), Y1(hist[j])); }\n" ++
    "    cg.strokeStyle = '#50e3c2'; cg.lineWidth = 1.6; cg.stroke();\n" ++
    "  }\n" ++
    "\n" ++
    "  function frame(now) {\n" ++
    "    requestAnimationFrame(frame);\n" ++
    "    if (now - fpsT > 1000) { fps = framesN; framesN = 0; fpsT = now; var f = $('o-fps'); if (f) f.textContent = fps; }\n" ++
    "    tickStats();\n" ++
    "    if (!W) { resize(); return; }\n" ++
    "    drawBrain(now); drawArena(now); drawChart();\n" ++
    "  }\n" ++
    "  window.__swBrain = { get act() { return act; }, get N() { return N; } };\n" ++
    "  resize();\n" ++
    "  requestAnimationFrame(frame);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
