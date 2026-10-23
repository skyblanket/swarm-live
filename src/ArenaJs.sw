module ArenaJs

# GENERATED from src/arena.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() {
    "/* Swarm Arena — canvas renderer. Source of truth for src/ArenaJs.sw\n" ++
    "   (regenerate with: python3 scripts/embed_js.py src/arena.js ArenaJs src/ArenaJs.sw).\n" ++
    "\n" ++
    "   The server sends one compact frame every ~100ms:\n" ++
    "     h  heat bucket 0..4 per agent        e  [[from,to],...] recent real messages\n" ++
    "     ev [['k',i,pid] | ['u',i,pid,ms,gen]] kills and supervisor respawns\n" ++
    "     p c r m tot b  processes, crashes, restarts, msgs/s, total msgs, burst\n" ++
    "   Everything on screen is drawn from those; nothing is simulated. */\n" ++
    "(function () {\n" ++
    "  var N = 600, COLS = 30, ROWS = 20;\n" ++
    "  /* ?slow=6 plays every effect 6x slower (the data is still live) */\n" ++
    "  var SLOW = Number((location.search.match(/slow=([0-9.]+)/) || [0, 1])[1]) || 1;\n" ++
    "  var cv = document.getElementById('stage');\n" ++
    "  if (!cv) return;\n" ++
    "  var g = cv.getContext('2d');\n" ++
    "  var dpr = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "  var W = 0, H = 0, cell = 10, gx = 0, gy = 0, sup = { x: 0, y: 0 };\n" ++
    "\n" ++
    "  var lvl = new Float32Array(N), target = new Uint8Array(N);\n" ++
    "  var deadAt = new Float64Array(N), upAt = new Float64Array(N), hotAt = new Float64Array(N);\n" ++
    "  var comets = [], rings = [], sparks = [], beams = [];\n" ++
    "  var shake = 0, hover = -1, frames = 0, lastFrame = 0;\n" ++
    "  var restartMs = [], logQ = [], logTotal = 0;\n" ++
    "\n" ++
    "  function layout() {\n" ++
    "    W = cv.clientWidth; H = cv.clientHeight;\n" ++
    "    cv.width = W * dpr; cv.height = H * dpr;\n" ++
    "    g.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    var top = 100, pad = 24, panel = W > 900 ? 340 : 0, aw = W - panel;\n" ++
    "    cell = Math.floor(Math.min((aw - pad * 2) / COLS, (H - top - pad) / ROWS));\n" ++
    "    gx = Math.floor((aw - cell * COLS) / 2);\n" ++
    "    gy = top + Math.floor((H - top - pad - cell * ROWS) / 2);\n" ++
    "    sup.x = gx + cell * COLS / 2; sup.y = 62;\n" ++
    "  }\n" ++
    "  window.addEventListener('resize', layout);\n" ++
    "  layout();\n" ++
    "\n" ++
    "  function cx(i) { return gx + (i % COLS) * cell + cell / 2; }\n" ++
    "  function cy(i) { return gy + Math.floor(i / COLS) * cell + cell / 2; }\n" ++
    "\n" ++
    "  /* ---------- effects ---------- */\n" ++
    "  function explode(i, now) {\n" ++
    "    deadAt[i] = now;\n" ++
    "    rings.push({ x: cx(i), y: cy(i), t: now, c: '255,70,50', r: cell * 4, d: 700 * SLOW });\n" ++
    "    for (var k = 0; k < 14; k++) {\n" ++
    "      var a = Math.random() * 6.283, v = 40 + Math.random() * 120;\n" ++
    "      sparks.push({ x: cx(i), y: cy(i), vx: Math.cos(a) * v, vy: Math.sin(a) * v, t: now, d: (500 + Math.random() * 400) * SLOW });\n" ++
    "    }\n" ++
    "    beams.push({ i: i, t: now, c: '255,70,50', out: true, d: 450 * SLOW });\n" ++
    "  }\n" ++
    "  function respawn(i, now) {\n" ++
    "    upAt[i] = now; deadAt[i] = 0;\n" ++
    "    rings.push({ x: cx(i), y: cy(i), t: now, c: '60,255,150', r: cell * 3, d: 650 * SLOW });\n" ++
    "    beams.push({ i: i, t: now, c: '60,255,150', out: false, d: 450 * SLOW });\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- frames from the server ---------- */\n" ++
    "  function addLog(cls, html) { logQ.push([cls, html]); logTotal++; }\n" ++
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  window.SwEvents.frame = function (d) {\n" ++
    "    var now = performance.now(), i, k;\n" ++
    "    if (d.h) for (i = 0; i < N && i < d.h.length; i++) target[i] = d.h[i];\n" ++
    "    var E = d.e || [];\n" ++
    "    for (k = 0; k < E.length; k++) {\n" ++
    "      comets.push({ a: E[k][0], b: E[k][1], t: now + Math.random() * 90, d: 320 + Math.random() * 160, bow: (Math.random() - 0.5) * 80 });\n" ++
    "      hotAt[E[k][1]] = now;\n" ++
    "    }\n" ++
    "    if (comets.length > 900) comets.splice(0, comets.length - 900);\n" ++
    "    var V = d.ev || [], kills = 0;\n" ++
    "    for (k = 0; k < V.length; k++) {\n" ++
    "      var e = V[k];\n" ++
    "      if (e[0] === 'k') { kills++; if (!deadAt[e[1]]) explode(e[1], now); addLog('k', 'killed #' + e[1] + ' ' + e[2]); }\n" ++
    "      else {\n" ++
    "        respawn(e[1], now);\n" ++
    "        restartMs.push(e[3]); if (restartMs.length > 200) restartMs.shift();\n" ++
    "        addLog('u', 'respawned #' + e[1] + ' ' + e[2] + ' in ' + e[3] + 'ms &middot; gen ' + e[4]);\n" ++
    "      }\n" ++
    "    }\n" ++
    "    if (kills >= 8) shake = Math.max(shake, Math.min(14, kills / 4));\n" ++
    "    stat('s-proc', d.p); stat('s-msgs', d.m); stat('s-tot', d.tot);\n" ++
    "    stat('s-crash', d.c); stat('s-rest', d.r);\n" ++
    "    var avg = 0; for (k = 0; k < restartMs.length; k++) avg += restartMs[k];\n" ++
    "    stat('s-ms', restartMs.length ? (avg / restartMs.length).toFixed(1) + ' ms' : '-');\n" ++
    "    setBurst(d.b);\n" ++
    "    flushLog();\n" ++
    "  };\n" ++
    "\n" ++
    "  function fmt(n) { n = Math.round(n || 0); return n >= 1e6 ? (n / 1e6).toFixed(2) + 'M' : n >= 1e4 ? (n / 1e3).toFixed(1) + 'k' : String(n); }\n" ++
    "  function stat(id, v) { var el = document.getElementById(id); if (el) el.textContent = typeof v === 'string' ? v : fmt(v); }\n" ++
    "  function flushLog() {\n" ++
    "    var el = document.getElementById('log'); if (!el || !logQ.length) return;\n" ++
    "    var q = logQ; logQ = [];\n" ++
    "    var extra = q.length > 10 ? q.length - 10 : 0, keep = q.slice(-10), html = '';\n" ++
    "    for (var i = keep.length - 1; i >= 0; i--) html += '<div class=\"ln ' + keep[i][0] + '\">' + keep[i][1] + '</div>';\n" ++
    "    if (extra) html = '<div class=\"ln m\">... and ' + extra + ' more</div>' + html;\n" ++
    "    el.innerHTML = html + el.innerHTML;\n" ++
    "    while (el.children.length > 16) el.removeChild(el.lastChild);\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- controls: instant, client-side feedback first ---------- */\n" ++
    "  function setBurst(b) {\n" ++
    "    var bs = document.querySelectorAll('[data-burst]');\n" ++
    "    for (var i = 0; i < bs.length; i++) bs[i].classList.toggle('on', Number(bs[i].getAttribute('data-burst')) === b);\n" ++
    "  }\n" ++
    "  document.addEventListener('click', function (e) {\n" ++
    "    var t = e.target.closest ? e.target.closest('[data-burst],[data-kill]') : null;\n" ++
    "    if (!t) return;\n" ++
    "    if (t.hasAttribute('data-burst')) {\n" ++
    "      var b = Number(t.getAttribute('data-burst')); setBurst(b); window.swSend('burst', { n: b });\n" ++
    "    } else {\n" ++
    "      var k = Number(t.getAttribute('data-kill'));\n" ++
    "      shake = Math.max(shake, k >= 200 ? 22 : 12);\n" ++
    "      window.swSend('chaos', { k: k });\n" ++
    "    }\n" ++
    "  });\n" ++
    "  function cellAt(ev) {\n" ++
    "    var r = cv.getBoundingClientRect(), x = ev.clientX - r.left - gx, y = ev.clientY - r.top - gy;\n" ++
    "    var c = Math.floor(x / cell), rw = Math.floor(y / cell);\n" ++
    "    return (c < 0 || c >= COLS || rw < 0 || rw >= ROWS) ? -1 : rw * COLS + c;\n" ++
    "  }\n" ++
    "  cv.addEventListener('mousemove', function (ev) { hover = cellAt(ev); cv.style.cursor = hover >= 0 ? 'crosshair' : 'default'; });\n" ++
    "  cv.addEventListener('mouseleave', function () { hover = -1; });\n" ++
    "  cv.addEventListener('mousedown', function (ev) {\n" ++
    "    var i = cellAt(ev); if (i < 0) return;\n" ++
    "    explode(i, performance.now()); shake = Math.max(shake, 3);\n" ++
    "    window.swSend('kill', { key: String(i) });\n" ++
    "  });\n" ++
    "\n" ++
    "  /* ---------- draw loop ---------- */\n" ++
    "  function mix(a, b, t) { return Math.round(a + (b - a) * t); }\n" ++
    "  var RAMP = [[14, 18, 23], [18, 48, 74], [22, 89, 160], [24, 160, 216], [154, 240, 255]];\n" ++
    "  function heatColor(l) {\n" ++
    "    l = Math.max(0, Math.min(3.999, l));\n" ++
    "    var i = Math.floor(l), t = l - i, a = RAMP[i], b = RAMP[i + 1];\n" ++
    "    return 'rgb(' + mix(a[0], b[0], t) + ',' + mix(a[1], b[1], t) + ',' + mix(a[2], b[2], t) + ')';\n" ++
    "  }\n" ++
    "  function frame(now) {\n" ++
    "    requestAnimationFrame(frame);\n" ++
    "    var dt = Math.min(0.05, (now - (lastFrame || now)) / 1000); lastFrame = now; frames++;\n" ++
    "    g.save();\n" ++
    "    g.clearRect(0, 0, W, H);\n" ++
    "    if (shake > 0.2) { g.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake); shake *= 0.9; } else shake = 0;\n" ++
    "\n" ++
    "    /* supervisor node */\n" ++
    "    var pulse = 0.5 + 0.5 * Math.sin(now / 400);\n" ++
    "    g.beginPath(); g.arc(sup.x, sup.y, 20 + pulse * 2, 0, 6.283);\n" ++
    "    g.strokeStyle = 'rgba(180,200,255,' + (0.35 + pulse * 0.2) + ')'; g.lineWidth = 1.5; g.stroke();\n" ++
    "    g.beginPath(); g.arc(sup.x, sup.y, 5, 0, 6.283); g.fillStyle = '#c7d2fe'; g.fill();\n" ++
    "    g.fillStyle = 'rgba(200,210,255,0.7)'; g.font = '10px ui-monospace,Menlo,monospace'; g.textAlign = 'center';\n" ++
    "    g.fillText('SUPERVISOR', sup.x, sup.y + 38);\n" ++
    "\n" ++
    "    /* cells */\n" ++
    "    var i, x, y, s = cell * 0.8, off = (cell - s) / 2;\n" ++
    "    for (i = 0; i < N; i++) {\n" ++
    "      lvl[i] += (target[i] - lvl[i]) * Math.min(1, dt * 9);\n" ++
    "      x = gx + (i % COLS) * cell + off; y = gy + Math.floor(i / COLS) * cell + off;\n" ++
    "      var dead = deadAt[i] && now - deadAt[i] < 1500 * SLOW;\n" ++
    "      if (dead) {\n" ++
    "        var f = 1 - Math.min(1, (now - deadAt[i]) / (1500 * SLOW));\n" ++
    "        g.fillStyle = 'rgba(255,60,40,' + (0.15 + f * 0.8) + ')'; g.fillRect(x, y, s, s);\n" ++
    "        g.strokeStyle = 'rgba(0,0,0,0.7)'; g.beginPath(); g.moveTo(x, y); g.lineTo(x + s, y + s); g.moveTo(x + s, y); g.lineTo(x, y + s); g.stroke();\n" ++
    "        continue;\n" ++
    "      }\n" ++
    "      g.fillStyle = heatColor(lvl[i]); g.fillRect(x, y, s, s);\n" ++
    "      var up = upAt[i] ? 1 - (now - upAt[i]) / (900 * SLOW) : 0;\n" ++
    "      if (up > 0) { g.fillStyle = 'rgba(120,255,180,' + up * 0.85 + ')'; g.fillRect(x, y, s, s); }\n" ++
    "    }\n" ++
    "    /* glow on the hot ones */\n" ++
    "    g.globalCompositeOperation = 'lighter';\n" ++
    "    for (i = 0; i < N; i++) {\n" ++
    "      if (lvl[i] < 2.4) continue;\n" ++
    "      var a = (lvl[i] - 2.4) / 1.6 * 0.45;\n" ++
    "      var gr = g.createRadialGradient(cx(i), cy(i), 0, cx(i), cy(i), cell * 1.6);\n" ++
    "      gr.addColorStop(0, 'rgba(90,215,240,' + a + ')'); gr.addColorStop(1, 'rgba(90,215,240,0)');\n" ++
    "      g.fillStyle = gr; g.fillRect(cx(i) - cell * 1.6, cy(i) - cell * 1.6, cell * 3.2, cell * 3.2);\n" ++
    "    }\n" ++
    "\n" ++
    "    /* real message comets: from -> to along a bowed arc, with a tail */\n" ++
    "    for (i = comets.length - 1; i >= 0; i--) {\n" ++
    "      var c = comets[i], p = (now - c.t) / c.d;\n" ++
    "      if (p < 0) continue;\n" ++
    "      if (p >= 1) { comets.splice(i, 1); continue; }\n" ++
    "      var x0 = cx(c.a), y0 = cy(c.a), x1 = cx(c.b), y1 = cy(c.b);\n" ++
    "      var mx = (x0 + x1) / 2 + c.bow, my = (y0 + y1) / 2 - Math.abs(c.bow);\n" ++
    "      for (var tl = 0; tl < 4; tl++) {\n" ++
    "        var q = Math.max(0, p - tl * 0.04), u = 1 - q;\n" ++
    "        var px = u * u * x0 + 2 * u * q * mx + q * q * x1, py = u * u * y0 + 2 * u * q * my + q * q * y1;\n" ++
    "        g.fillStyle = 'rgba(160,235,255,' + (0.75 - tl * 0.18) * (1 - p * 0.4) + ')';\n" ++
    "        g.beginPath(); g.arc(px, py, 2.1 - tl * 0.35, 0, 6.283); g.fill();\n" ++
    "      }\n" ++
    "    }\n" ++
    "\n" ++
    "    /* supervisor beams: red out on death, green back on respawn */\n" ++
    "    for (i = beams.length - 1; i >= 0; i--) {\n" ++
    "      var b = beams[i], bp = (now - b.t) / b.d;\n" ++
    "      if (bp >= 1) { beams.splice(i, 1); continue; }\n" ++
    "      var ax = b.out ? cx(b.i) : sup.x, ay = b.out ? cy(b.i) : sup.y;\n" ++
    "      var bx = b.out ? sup.x : cx(b.i), by = b.out ? sup.y : cy(b.i);\n" ++
    "      var hx = ax + (bx - ax) * bp, hy = ay + (by - ay) * bp;\n" ++
    "      g.strokeStyle = 'rgba(' + b.c + ',' + (0.55 * (1 - bp)) + ')'; g.lineWidth = 1.2;\n" ++
    "      g.beginPath(); g.moveTo(ax, ay); g.lineTo(hx, hy); g.stroke();\n" ++
    "      g.fillStyle = 'rgba(' + b.c + ',' + (1 - bp) + ')'; g.beginPath(); g.arc(hx, hy, 2.6, 0, 6.283); g.fill();\n" ++
    "    }\n" ++
    "    g.globalCompositeOperation = 'source-over';\n" ++
    "\n" ++
    "    /* shockwave rings + sparks */\n" ++
    "    for (i = rings.length - 1; i >= 0; i--) {\n" ++
    "      var rg = rings[i], rp = (now - rg.t) / rg.d;\n" ++
    "      if (rp >= 1) { rings.splice(i, 1); continue; }\n" ++
    "      g.strokeStyle = 'rgba(' + rg.c + ',' + (1 - rp) + ')'; g.lineWidth = 3 * (1 - rp) + 0.5;\n" ++
    "      g.beginPath(); g.arc(rg.x, rg.y, rg.r * rp, 0, 6.283); g.stroke();\n" ++
    "    }\n" ++
    "    for (i = sparks.length - 1; i >= 0; i--) {\n" ++
    "      var sp = sparks[i], spp = (now - sp.t) / sp.d;\n" ++
    "      if (spp >= 1) { sparks.splice(i, 1); continue; }\n" ++
    "      var tt = (now - sp.t) / 1000 / SLOW;\n" ++
    "      g.fillStyle = 'rgba(255,' + mix(200, 70, spp) + ',60,' + (1 - spp) + ')';\n" ++
    "      g.fillRect(sp.x + sp.vx * tt, sp.y + sp.vy * tt + 60 * tt * tt, 2.4, 2.4);\n" ++
    "    }\n" ++
    "\n" ++
    "    /* hover label */\n" ++
    "    if (hover >= 0) {\n" ++
    "      g.strokeStyle = 'rgba(255,255,255,0.9)'; g.lineWidth = 1.5;\n" ++
    "      g.strokeRect(gx + (hover % COLS) * cell + 1, gy + Math.floor(hover / COLS) * cell + 1, cell - 2, cell - 2);\n" ++
    "      g.fillStyle = '#fff'; g.font = '11px ui-monospace,Menlo,monospace'; g.textAlign = 'left';\n" ++
    "      g.fillText('agent #' + hover + ' - click to kill', Math.min(W - 160, cx(hover) + 10), Math.max(14, cy(hover) - 10));\n" ++
    "    }\n" ++
    "    g.restore();\n" ++
    "  }\n" ++
    "  requestAnimationFrame(frame);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
