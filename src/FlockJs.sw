module FlockJs

# GENERATED from src/flock.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() {
    "/* Flock - canvas renderer. Source of truth for src/FlockJs.sw\n" ++
    "   (python3 scripts/embed_js.py src/flock.js FlockJs src/FlockJs.sw).\n" ++
    "\n" ++
    "   One frame ~every 33ms from the server:\n" ++
    "     p  flat [x0,y0,x1,y1,...] boid positions in world units (1600 x 900)\n" ++
    "     q  [[x,y,kind,hue],...] live predators (kind 0 repel, 1 attract, 2 blast)\n" ++
    "     o  flock order (alignment) x1000     s  avg speed x100     m  mode\n" ++
    "   Every boid on screen is a real swarmrt process. */\n" ++
    "(function () {\n" ++
    "  var WW = 1600, WH = 900;\n" ++
    "  var cv = document.getElementById('sky');\n" ++
    "  if (!cv) return;\n" ++
    "  var g = cv.getContext('2d');\n" ++
    "  var dpr = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "  var W = 0, H = 0, sc = 1, ox = 0, oy = 0;\n" ++
    "  var prev = null, cur = null, curT = 0, interval = 33, nB = 0;\n" ++
    "  var preds = [], rings = [], frames = 0, fpsT = performance.now();\n" ++
    "  var me = { x: -1, y: -1, down: false, sent: 0 };\n" ++
    "\n" ++
    "  function layout() {\n" ++
    "    W = cv.clientWidth; H = cv.clientHeight;\n" ++
    "    cv.width = W * dpr; cv.height = H * dpr;\n" ++
    "    g.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    sc = Math.max(W / WW, H / WH);\n" ++
    "    ox = (W - WW * sc) / 2; oy = (H - WH * sc) / 2;\n" ++
    "    g.fillStyle = '#06070a'; g.fillRect(0, 0, W, H);\n" ++
    "  }\n" ++
    "  window.addEventListener('resize', layout);\n" ++
    "  layout();\n" ++
    "\n" ++
    "  function el(id) { return document.getElementById(id); }\n" ++
    "  function set(id, v) { var e = el(id); if (e) e.textContent = v; }\n" ++
    "\n" ++
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  window.SwEvents.frame = function (d) {\n" ++
    "    var now = performance.now();\n" ++
    "    if (curT) interval = Math.max(16, Math.min(120, now - curT));\n" ++
    "    prev = cur; cur = d.p; curT = now; nB = d.p.length / 2;\n" ++
    "    preds = d.q || [];\n" ++
    "    set('s-n', nB);\n" ++
    "    set('s-ord', (d.o / 10).toFixed(1) + '%');\n" ++
    "    var m = el('m-ord'); if (m) m.style.width = (d.o / 10) + '%';\n" ++
    "    set('s-spd', (d.s / 100).toFixed(2));\n" ++
    "    var bs = document.querySelectorAll('[data-mode]');\n" ++
    "    for (var i = 0; i < bs.length; i++) bs[i].classList.toggle('on', Number(bs[i].getAttribute('data-mode')) === d.m);\n" ++
    "    frames++;\n" ++
    "  };\n" ++
    "  window.SwEvents.presence = function (n) { set('s-view', n); };\n" ++
    "\n" ++
    "  /* ---------- input: instant local cursor, throttled to the server ---------- */\n" ++
    "  function world(ev) {\n" ++
    "    var r = cv.getBoundingClientRect();\n" ++
    "    return { x: ((ev.clientX - r.left) - ox) / sc, y: ((ev.clientY - r.top) - oy) / sc, sx: ev.clientX - r.left, sy: ev.clientY - r.top };\n" ++
    "  }\n" ++
    "  function send(force) {\n" ++
    "    var now = performance.now();\n" ++
    "    if (!force && now - me.sent < 30) return;\n" ++
    "    me.sent = now;\n" ++
    "    window.swSend('ptr', { x: Math.min(1, Math.max(0, me.x / WW)), y: Math.min(1, Math.max(0, me.y / WH)), k: me.down ? 1 : 0 });\n" ++
    "  }\n" ++
    "  cv.addEventListener('pointermove', function (ev) { var w = world(ev); me.x = w.x; me.y = w.y; me.sx = w.sx; me.sy = w.sy; send(false); });\n" ++
    "  cv.addEventListener('pointerdown', function (ev) {\n" ++
    "    var w = world(ev); me.x = w.x; me.y = w.y; me.sx = w.sx; me.sy = w.sy; me.down = true;\n" ++
    "    try { cv.setPointerCapture(ev.pointerId); } catch (e) {} send(true);\n" ++
    "  });\n" ++
    "  cv.addEventListener('pointerup', function () { me.down = false; send(true); });\n" ++
    "  cv.addEventListener('pointerleave', function () { if (!me.down) { me.x = me.y = -1; } });\n" ++
    "  document.addEventListener('click', function (e) {\n" ++
    "    var t = e.target.closest ? e.target.closest('[data-mode],[data-blast]') : null;\n" ++
    "    if (!t) return;\n" ++
    "    if (t.hasAttribute('data-mode')) {\n" ++
    "      var m = Number(t.getAttribute('data-mode'));\n" ++
    "      var bs = document.querySelectorAll('[data-mode]');\n" ++
    "      for (var i = 0; i < bs.length; i++) bs[i].classList.toggle('on', Number(bs[i].getAttribute('data-mode')) === m);\n" ++
    "      window.swSend('mode', { m: m });\n" ++
    "    } else {\n" ++
    "      var bx = me.x >= 0 ? me.x : WW / 2, by = me.y >= 0 ? me.y : WH / 2;\n" ++
    "      rings.push({ x: bx, y: by, t: performance.now(), hue: 20 });\n" ++
    "      window.swSend('blast', { x: bx / WW, y: by / WH });\n" ++
    "    }\n" ++
    "  });\n" ++
    "\n" ++
    "  /* ---------- draw ---------- */\n" ++
    "  function frame(now) {\n" ++
    "    requestAnimationFrame(frame);\n" ++
    "    if (now - fpsT > 1000) { set('s-fps', Math.round(frames * 1000 / (now - fpsT))); frames = 0; fpsT = now; }\n" ++
    "    /* fading trails */\n" ++
    "    g.globalCompositeOperation = 'source-over';\n" ++
    "    g.fillStyle = 'rgba(6,7,10,0.2)'; g.fillRect(0, 0, W, H);\n" ++
    "    if (!cur) return;\n" ++
    "    var t = prev ? Math.min(1.2, (now - curT) / interval) : 1;\n" ++
    "    g.globalCompositeOperation = 'lighter';\n" ++
    "    var n = nB, i, x, y, dx, dy, a, c, s, sz = Math.max(4.5, 6.5 * sc);\n" ++
    "    for (i = 0; i < n; i++) {\n" ++
    "      var cx = cur[i * 2], cy = cur[i * 2 + 1];\n" ++
    "      dx = 0; dy = 0;\n" ++
    "      if (prev) {\n" ++
    "        dx = cx - prev[i * 2]; dy = cy - prev[i * 2 + 1];\n" ++
    "        if (dx > WW / 2 || dx < -WW / 2 || dy > WH / 2 || dy < -WH / 2) { dx = 0; dy = 0; }\n" ++
    "      }\n" ++
    "      x = ox + (cx + dx * (t - 1)) * sc; y = oy + (cy + dy * (t - 1)) * sc;\n" ++
    "      if (x < -20 || y < -20 || x > W + 20 || y > H + 20) continue;\n" ++
    "      a = (dx === 0 && dy === 0) ? 0 : Math.atan2(dy, dx);\n" ++
    "      var hue = ((a * 57.3) + 200 + (i % 37) * 3.2 + 360) % 360;\n" ++
    "      c = Math.cos(a); s = Math.sin(a);\n" ++
    "      g.fillStyle = 'hsla(' + hue + ',85%,62%,0.85)';\n" ++
    "      g.beginPath();\n" ++
    "      g.moveTo(x + c * sz, y + s * sz);\n" ++
    "      g.lineTo(x - c * sz * 0.7 - s * sz * 0.5, y - s * sz * 0.7 + c * sz * 0.5);\n" ++
    "      g.lineTo(x - c * sz * 0.7 + s * sz * 0.5, y - s * sz * 0.7 - c * sz * 0.5);\n" ++
    "      g.closePath(); g.fill();\n" ++
    "    }\n" ++
    "    g.globalCompositeOperation = 'source-over';\n" ++
    "\n" ++
    "    /* predators / attractors / blasts (from the server, so everyone sees everyone) */\n" ++
    "    for (i = 0; i < preds.length; i++) {\n" ++
    "      var p = preds[i], px = ox + p[0] * sc, py = oy + p[1] * sc, pulse = 0.5 + 0.5 * Math.sin(now / 150 + i);\n" ++
    "      if (p[2] === 1) {\n" ++
    "        for (var k = 0; k < 3; k++) {\n" ++
    "          var rr = ((now / 9 + k * 40) % 120) * sc;\n" ++
    "          g.strokeStyle = 'hsla(' + p[3] + ',90%,65%,' + (1 - rr / (120 * sc)) * 0.6 + ')'; g.lineWidth = 1.5;\n" ++
    "          g.beginPath(); g.arc(px, py, 120 * sc - rr, 0, 6.283); g.stroke();\n" ++
    "        }\n" ++
    "        g.fillStyle = 'hsl(' + p[3] + ',90%,70%)'; g.beginPath(); g.arc(px, py, 5, 0, 6.283); g.fill();\n" ++
    "      } else if (p[2] === 0) {\n" ++
    "        g.strokeStyle = 'hsla(' + p[3] + ',90%,65%,0.55)'; g.lineWidth = 1.5; g.setLineDash([4, 5]);\n" ++
    "        g.beginPath(); g.arc(px, py, 173 * sc * (0.96 + pulse * 0.04), 0, 6.283); g.stroke(); g.setLineDash([]);\n" ++
    "        g.fillStyle = 'hsl(' + p[3] + ',90%,65%)'; g.beginPath(); g.arc(px, py, 4, 0, 6.283); g.fill();\n" ++
    "      }\n" ++
    "    }\n" ++
    "    for (i = rings.length - 1; i >= 0; i--) {\n" ++
    "      var b = rings[i], bp = (now - b.t) / 700;\n" ++
    "      if (bp >= 1) { rings.splice(i, 1); continue; }\n" ++
    "      g.strokeStyle = 'hsla(' + b.hue + ',100%,60%,' + (1 - bp) + ')'; g.lineWidth = 3 * (1 - bp) + 0.5;\n" ++
    "      g.beginPath(); g.arc(ox + b.x * sc, oy + b.y * sc, 400 * sc * bp, 0, 6.283); g.stroke();\n" ++
    "    }\n" ++
    "    /* my own cursor: drawn locally so it never lags */\n" ++
    "    if (me.x >= 0) {\n" ++
    "      g.strokeStyle = me.down ? 'rgba(120,230,255,0.95)' : 'rgba(255,255,255,0.9)'; g.lineWidth = 1.5;\n" ++
    "      g.beginPath(); g.arc(me.sx, me.sy, me.down ? 11 : 7, 0, 6.283); g.stroke();\n" ++
    "    }\n" ++
    "  }\n" ++
    "  requestAnimationFrame(frame);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
