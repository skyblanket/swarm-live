module LifeJs

# GENERATED from src/life.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() {
    "/* Life at Scale - client. Source of truth for src/LifeJs.sw\n" ++
    "   (python3 scripts/embed_js.py src/life.js LifeJs src/LifeJs.sw).\n" ++
    "\n" ++
    "   One frame per ~33ms+ from the server:\n" ++
    "     w   board side            gen  generation number\n" ++
    "     b   cells packed 30 per int (MSB first), row-major\n" ++
    "     pop live cells            procs processes alive in the node\n" ++
    "     gps generations/s         mps cell messages/s (10 per cell per generation)\n" ++
    "     spms ms to spawn the board's processes\n" ++
    "     restarts crashes          from swarm_stats()\n" ++
    "     paused delay              controls echoed back\n" ++
    "     k   [cell idx] killed since last frame     r  [cell idx] respawned\n" ++
    "   Every square is a real swarmrt process. Nothing is simulated. */\n" ++
    "(function () {\n" ++
    "  var $ = function (id) { return document.getElementById(id); };\n" ++
    "  var cv = $('life-cv'), box = $('board');\n" ++
    "  if (!cv) return;\n" ++
    "  var g = cv.getContext('2d');\n" ++
    "  var dpr = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "  var off = document.createElement('canvas'), og = off.getContext('2d');\n" ++
    "  var W = 0, N = 0, cs = 1, bw = 0, bh = 0, img = null;\n" ++
    "  var cells = new Uint8Array(0), age = new Uint16Array(0), trail = new Float32Array(0);\n" ++
    "  var rings = [], shake = 0, last = null, framesN = 0, fps = 0, fpsT = performance.now(), dirty = true;\n" ++
    "  /* ?slow=6 plays the kill / respawn effects 6x slower (the simulation is unchanged) */\n" ++
    "  var SLOW = Number((location.search.match(/slow=([0-9.]+)/) || [0, 1])[1]) || 1;\n" ++
    "  var stats = {}, painting = false, paintVal = 1, pending = {}, paintT = 0, hoverIdx = -1;\n" ++
    "\n" ++
    "  function fmt(n) { n = Math.round(n || 0); if (n >= 1e9) return (n / 1e9).toFixed(2) + 'B'; if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k'; return String(n); }\n" ++
    "  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }\n" ++
    "\n" ++
    "  /* ---------- sizing ---------- */\n" ++
    "  function resize() {\n" ++
    "    bw = box.clientWidth; bh = box.clientHeight;\n" ++
    "    if (!W) return;\n" ++
    "    cs = Math.max(1, Math.min((bw - 40) / W, (bh - 40) / W));\n" ++
    "    if (cs >= 3) cs = Math.floor(cs * 2) / 2;\n" ++
    "    var px = Math.floor(W * cs);\n" ++
    "    cv.style.width = px + 'px'; cv.style.height = px + 'px';\n" ++
    "    cv.width = px * dpr; cv.height = px * dpr;\n" ++
    "    g.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    dirty = true;\n" ++
    "  }\n" ++
    "  if (window.ResizeObserver) new ResizeObserver(resize).observe(box); else window.addEventListener('resize', resize);\n" ++
    "\n" ++
    "  function setBoard(w) {\n" ++
    "    W = w; N = w * w;\n" ++
    "    cells = new Uint8Array(N); age = new Uint16Array(N); trail = new Float32Array(N);\n" ++
    "    off.width = w; off.height = w; img = og.createImageData(w, w);\n" ++
    "    rings = []; resize();\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- frames ---------- */\n" ++
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  window.SwEvents.frame = function (d) {\n" ++
    "    var now = performance.now(), i, k, v, base;\n" ++
    "    if (d.w !== W) setBoard(d.w);\n" ++
    "    for (i = 0; i < d.b.length; i++) {\n" ++
    "      v = d.b[i]; base = i * 30;\n" ++
    "      for (k = 0; k < 30; k++) {\n" ++
    "        var idx = base + k; if (idx >= N) break;\n" ++
    "        var s = (v >> (29 - k)) & 1;\n" ++
    "        if (s) { age[idx] = age[idx] < 65000 ? age[idx] + 1 : age[idx]; trail[idx] = 1; } else { age[idx] = 0; }\n" ++
    "        cells[idx] = s;\n" ++
    "      }\n" ++
    "    }\n" ++
    "    last = d; framesN++; dirty = true;\n" ++
    "    stat('procs', d.procs, fmtc, 'spawned in ' + fmtc(d.spms) + ' ms', 'up');\n" ++
    "    stat('gps', d.gps, function (x) { return x.toFixed(x < 10 ? 1 : 0); }, 'generation ' + fmtc(d.gen), '');\n" ++
    "    stat('mps', d.mps, fmt, '10 messages per cell per generation', '');\n" ++
    "    stat('pop', d.pop, fmtc, (d.pop / N * 100).toFixed(1) + '% of the board alive', '');\n" ++
    "    stat('heal', d.restarts, fmtc, d.crashes ? fmtc(d.crashes) + ' crashes so far' : 'nothing has crashed yet', d.crashes ? 'bad' : '');\n" ++
    "    var hs = $('h-sleep'); if (hs) hs.innerHTML = d.sl ? '<b>' + fmtc(d.sl) + '</b> idle processes parked (last batch: ' + fmtc(d.sll) + ' spawned in <b>' + fmtc(d.slms) + ' ms</b>). The board is still running.' : 'Parked processes cost ~10-20 KB each. The board keeps running while you stack tens of thousands of them next to it. The runtime ceiling is 100,000.';\n" ++
    "    var bh2 = $('bh'); if (bh2) bh2.innerHTML = '<b>' + W + ' &times; ' + W + '</b> &middot; ' + fmtc(N) + ' processes &middot; generation ' + fmtc(d.gen) + (d.paused ? ' &middot; paused' : '');\n" ++
    "    var sz = document.querySelectorAll('[data-size]'), sp = document.querySelectorAll('[data-speed]');\n" ++
    "    for (i = 0; i < sz.length; i++) sz[i].classList.toggle('on', Number(sz[i].getAttribute('data-size')) === W);\n" ++
    "    for (i = 0; i < sp.length; i++) sp[i].classList.toggle('on', Number(sp[i].getAttribute('data-speed')) === d.delay);\n" ++
    "    var pb = $('b-pause'); if (pb) pb.textContent = d.paused ? 'Resume' : 'Pause';\n" ++
    "  };\n" ++
    "\n" ++
    "  /* kills and respawns are announced the moment they happen, not with the next generation */\n" ++
    "  window.SwEvents.kills = function (d) {\n" ++
    "    var now = performance.now();\n" ++
    "    for (var i = 0; i < d.k.length; i++) { var a = d.k[i]; cells[a] = 0; age[a] = 0; trail[a] = 0; if (rings.length < 900) rings.push({ i: a, t: now, c: '255,77,77', big: d.n < 150 }); }\n" ++
    "    if (d.n > 40) shake = Math.min(14, d.n / 80 + 4);\n" ++
    "    dirty = true;\n" ++
    "  };\n" ++
    "  window.SwEvents.revived = function (d) {\n" ++
    "    var now = performance.now();\n" ++
    "    for (var i = 0; i < d.r.length; i++) if (rings.length < 900) rings.push({ i: d.r[i], t: now, c: '80,227,194', big: d.n < 150 });\n" ++
    "    dirty = true;\n" ++
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
    "      var s = stats[id]; s.cur += (s.tgt - s.cur) * 0.22; if (Math.abs(s.tgt - s.cur) < 0.5) s.cur = s.tgt;\n" ++
    "      var t = s.fmt(s.cur), el = $('v-' + id);\n" ++
    "      if (el && t !== s.shown) { el.textContent = t; s.shown = t; }\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- drawing ---------- */\n" ++
    "  function paintImage() {\n" ++
    "    var data = img.data, i, p;\n" ++
    "    for (i = 0; i < N; i++) {\n" ++
    "      p = i * 4;\n" ++
    "      if (cells[i]) {\n" ++
    "        var a = age[i], r, gg, b;\n" ++
    "        if (a < 3) { r = 255; gg = 255; b = 255; }\n" ++
    "        else if (a < 14) { var t = (a - 3) / 11; r = 255 - t * 175; gg = 255 - t * 45; b = 255; }\n" ++
    "        else if (a < 90) { var t2 = (a - 14) / 76; r = 80 + t2 * 80; gg = 210 - t2 * 120; b = 255; }\n" ++
    "        else { r = 150; gg = 90; b = 240; }\n" ++
    "        data[p] = r; data[p + 1] = gg; data[p + 2] = b; data[p + 3] = 255;\n" ++
    "      } else {\n" ++
    "        var tr = trail[i];\n" ++
    "        if (tr > 0.02) { trail[i] = tr * 0.9; data[p] = 8 + tr * 30; data[p + 1] = 10 + tr * 70; data[p + 2] = 18 + tr * 120; }\n" ++
    "        else { trail[i] = 0; data[p] = 6; data[p + 1] = 7; data[p + 2] = 11; }\n" ++
    "        data[p + 3] = 255;\n" ++
    "      }\n" ++
    "    }\n" ++
    "    og.putImageData(img, 0, 0);\n" ++
    "  }\n" ++
    "\n" ++
    "  function draw(now) {\n" ++
    "    requestAnimationFrame(draw);\n" ++
    "    if (now - fpsT > 1000) { fps = framesN; framesN = 0; fpsT = now; var f = $('o-fps'); if (f) f.textContent = fps; }\n" ++
    "    tickStats();\n" ++
    "    if (!W || !img) return;\n" ++
    "    var anyTrail = dirty || rings.length || shake > 0.2;\n" ++
    "    if (!anyTrail) return;\n" ++
    "    paintImage(); dirty = false;\n" ++
    "    var px = W * cs;\n" ++
    "    g.save();\n" ++
    "    if (shake > 0.2) { g.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake); shake *= 0.9; } else shake = 0;\n" ++
    "    g.imageSmoothingEnabled = cs < 2;\n" ++
    "    g.clearRect(-20, -20, px + 40, px + 40);\n" ++
    "    g.drawImage(off, 0, 0, px, px);\n" ++
    "    for (var i = rings.length - 1; i >= 0; i--) {\n" ++
    "      var r = rings[i], t = (now - r.t) / (700 * SLOW);\n" ++
    "      if (t >= 1) { rings.splice(i, 1); continue; }\n" ++
    "      var cx = ((r.i % W) + 0.5) * cs, cy = (Math.floor(r.i / W) + 0.5) * cs;\n" ++
    "      g.strokeStyle = 'rgba(' + r.c + ',' + (1 - t) + ')'; g.lineWidth = Math.max(1, cs * 0.35) * (1 - t) + 0.5;\n" ++
    "      g.beginPath(); g.arc(cx, cy, Math.max(0.5, cs * 0.6 + (r.big ? cs * 5 + 8 : cs * 1.6 + 3) * t), 0, 6.2832); g.stroke();\n" ++
    "    }\n" ++
    "    if (hoverIdx >= 0) {\n" ++
    "      g.strokeStyle = 'rgba(255,255,255,0.8)'; g.lineWidth = 1;\n" ++
    "      g.strokeRect((hoverIdx % W) * cs - 1, Math.floor(hoverIdx / W) * cs - 1, cs + 2, cs + 2);\n" ++
    "    }\n" ++
    "    g.restore();\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- input: draw on the board ---------- */\n" ++
    "  function cellAt(e) {\n" ++
    "    var r = cv.getBoundingClientRect(), x = Math.floor((e.clientX - r.left) / cs), y = Math.floor((e.clientY - r.top) / cs);\n" ++
    "    return (x < 0 || y < 0 || x >= W || y >= W) ? -1 : y * W + x;\n" ++
    "  }\n" ++
    "  function flush() {\n" ++
    "    var ids = Object.keys(pending); if (!ids.length) return;\n" ++
    "    window.swSend('paint', { c: ids.join(','), v: paintVal }); pending = {};\n" ++
    "  }\n" ++
    "  function addPaint(e) {\n" ++
    "    var i = cellAt(e); hoverIdx = i; if (i < 0) return;\n" ++
    "    if (!pending[i]) { pending[i] = 1; cells[i] = paintVal; if (paintVal) { age[i] = 0; trail[i] = 1; } dirty = true; }\n" ++
    "    var now = performance.now(); if (now - paintT > 40) { paintT = now; flush(); }\n" ++
    "  }\n" ++
    "  cv.addEventListener('pointerdown', function (e) { painting = true; paintVal = e.shiftKey ? 0 : 1; try { cv.setPointerCapture(e.pointerId); } catch (x) {} addPaint(e); });\n" ++
    "  cv.addEventListener('pointermove', function (e) { if (painting) addPaint(e); else { hoverIdx = cellAt(e); dirty = true; } });\n" ++
    "  cv.addEventListener('pointerup', function () { painting = false; flush(); });\n" ++
    "  cv.addEventListener('pointerleave', function () { hoverIdx = -1; dirty = true; });\n" ++
    "\n" ++
    "  /* ---------- controls ---------- */\n" ++
    "  document.addEventListener('click', function (e) {\n" ++
    "    var t = e.target.closest ? e.target.closest('[data-size],[data-pat],[data-speed],[data-chaos],[data-sleepers],#b-pause,#b-release') : null;\n" ++
    "    if (!t) return;\n" ++
    "    if (t.hasAttribute('data-size')) { var w = Number(t.getAttribute('data-size')); var bh = $('bh'); if (bh) bh.innerHTML = 'spawning <b>' + fmtc(w * w) + '</b> processes...'; window.swSend('size', { w: w }); }\n" ++
    "    else if (t.hasAttribute('data-pat')) window.swSend('pattern', { name: t.getAttribute('data-pat') });\n" ++
    "    else if (t.hasAttribute('data-speed')) window.swSend('speed', { ms: Number(t.getAttribute('data-speed')) });\n" ++
    "    else if (t.hasAttribute('data-chaos')) { shake = Math.max(shake, 8); window.swSend('chaos', { p: Number(t.getAttribute('data-chaos')) }); }\n" ++
    "    else if (t.hasAttribute('data-sleepers')) window.swSend('sleepers', { n: Number(t.getAttribute('data-sleepers')) });\n" ++
    "    else if (t.id === 'b-release') window.swSend('release', {});\n" ++
    "    else if (t.id === 'b-pause') window.swSend('pause', {});\n" ++
    "  });\n" ++
    "  window.__swLife = { get cells() { return cells; }, get W() { return W; } };\n" ++
    "  requestAnimationFrame(draw);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
