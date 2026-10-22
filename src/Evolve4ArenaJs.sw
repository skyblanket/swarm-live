module Evolve4ArenaJs

# GENERATED from src/evolve4_arena.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() { part0() ++ part1() ++ part2() }

fun part0() {
    "/* The Arena - client. Source of truth for src/Evolve4ArenaJs.sw\n" ++
    "   (python3 scripts/embed_js.py src/evolve4_arena.js Evolve4ArenaJs src/Evolve4ArenaJs.sw).\n" ++
    "\n" ++
    "   Events:\n" ++
    "     live   {task 0 light / 1 chase / 2 fight, tick, T, b: bodies, tg: [x, y] target or null, sc: score*100, n: count}\n" ++
    "            a body is [hue, flat, health, pain, thrust*100, turn*100, bite*100]; flat has five numbers per node\n" ++
    "            [type, radius*10000, parent index, x, y] with x, y in thousandths of the world (type 6 core, 0 body,\n" ++
    "            1 spike, 2 armor, 3 fin, 4 mouth, 5 eye)\n" ++
    "     champ  {k pool, id, gen, sc: [light, chase, fight]*100, body: [one body], nn, nc, ph, mass}\n" ++
    "     stats  {pools: [[k, gen, [best l, c, f, its gen], [gen, bl, bc, bf, ml, mc, mf], ms per gen]], hist: per pool rows (newest first),\n" ++
    "             trials, up, procs, show: [k, id, gen, l, c, f]}\n" ++
    "*/\n" ++
    "(function () {\n" ++
    "  var $ = function (id) { return document.getElementById(id); };\n" ++
    "  var dpr = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "  var WS = 1.6;\n" ++
    "  var TASKS = [\n" ++
    "    { name: 'Swim to the light', sub: 'reach each glowing pellet; it is sensed exactly like food', unit: 'pellets' },\n" ++
    "    { name: 'Chase', sub: 'catch the prey; it runs faster after every catch', unit: 'caught' },\n" ++
    "    { name: 'Fight', sub: 'a duel with its pool’s runner-up: spikes wound, armor protects', unit: 'score' }\n" ++
    "  ];\n" ++
    "  var st = [null, null, null], trails = [[], [], []], cams = [null, null, null], preyPrev = null;\n" ++
    "  var champ = null, stats = null;\n" ++
    "  function hsl(h, s, l, a) { return 'hsla(' + h + ',' + s + '%,' + l + '%,' + (a === undefined ? 1 : a) + ')'; }\n" ++
    "  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }\n" ++
    "  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }\n" ++
    "\n" ++
    "  function build() {\n" ++
    "    var m = $('amain'); if (!m || m.children.length) return;\n" ++
    "    var h = '<div class=\"tasks\">';\n" ++
    "    for (var i = 0; i < 3; i++) {\n" ++
    "      h += '<div class=\"card task\"><canvas id=\"tc' + i + '\"></canvas><div class=\"th\"><div class=\"big\">' + TASKS[i].name + '</div><div class=\"sub\">' + TASKS[i].sub + '</div></div>' +\n" ++
    "        '<div class=\"sc\"><b id=\"ts' + i + '\">&ndash;</b><span id=\"tu' + i + '\">' + TASKS[i].unit + '</span></div><div class=\"pb\"><i id=\"tp' + i + '\" style=\"width:0\"></i></div></div>';\n" ++
    "    }\n" ++
    "    h += '</div><div class=\"row2\"><div class=\"card\"><h3>Now competing <span id=\"c-sub\">waiting for the first generation</span></h3><div class=\"champ\"><canvas id=\"c-cv\" width=\"240\" height=\"240\"></canvas><div style=\"flex:1;min-width:0\"><div id=\"c-title\" style=\"font-size:18px;font-weight:600\">&ndash;</div><div id=\"c-st\" style=\"font-size:12px;color:var(--mu);margin-top:2px\"></div><div class=\"kv\" id=\"c-kv\"></div></div></div></div>' +\n" ++
    "      '<div class=\"card\"><h3>Pools <span>each evolves on its own; every 8 generations its champion moves to the next pool</span></h3><table class=\"pt\" id=\"pt\"></table></div></div>' +\n" ++
    "      '<div class=\"card\" style=\"padding:14px 16px\"><h3>Progress <span>best score per generation, one line per pool</span></h3><div class=\"charts\">' +\n" ++
    "      '<div><div class=\"k\">Light: pellets reached</div><canvas id=\"ch0\"></canvas></div><div><div class=\"k\">Chase: prey caught</div><canvas id=\"ch1\"></canvas></div><div><div class=\"k\">Fight: damage dealt &minus; half taken</div><canvas id=\"ch2\"></canvas></div></div>' +\n" ++
    "      '<p class=\"cap\">In the open world most creatures could get by drifting through algae, so nothing pushed them to move well. Here every genome is <b>tested</b>: each generation it swims for the light, chases the prey, and fights two other genomes. Every trial is its own swarmrt process, so a generation runs thousands of trials at once. A genome’s fitness is its average rank over the three tasks. The best 6 survive unchanged; the rest of the pool is bred from tournament winners (two parents, meiosis, mutation), so bodies and brains change together. Bodies, physics, senses and the brain (with its evolved learning rule) are exactly those of Evolution 4, and the pools started from its evolved creatures. Every 15 seconds the pools’ champions are written to a file; each Evolution 4 island takes one in every 3000 ticks, so they compete in the open world too.</p></div>';\n" ++
    "    m.innerHTML = h;\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- events: keep the latest frame per task, and turn changes into effects ---------- */\n" ++
    "  var parts = [[], [], []], texts = [[], [], []], rings = [[], [], []];\n" ++
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  window.SwEvents.live = function (d) {\n" ++
    "    var t = d.task, prev = st[t], i;\n" ++
    "    if (!prev || d.tick < prev.tick) { trails[t] = []; cams[t] = null; parts[t] = []; texts[t] = []; rings[t] = []; prev = null; if (t === 1) preyPrev = null; }\n" ++
    "    if (prev && d.n > prev.n && prev.tg) {\n" ++
    "      var cx = prev.tg[0] / 1000, cy = prev.tg[1] / 1000, col = t === 0 ? [255, 214, 110] : [125, 255, 176];\n" ++
    "      burst(t, cx, cy, 26, col, 0.0035);\n" ++
    "      rings[t].push({ x: cx, y: cy, age: 0, col: col });\n" ++
    "      texts[t].push({ x: cx, y: cy, age: 0, txt: t === 0 ? '+1 pellet' : 'caught!', col: t === 0 ? '#ffd36b' : '#7dffb0' });\n" ++
    "    }\n" ++
    "    if (prev && t === 2) {\n" ++
    "      for (i = 0; i < d.b.length && i < prev.b.length; i++) {\n" ++
    "        var dh = prev.b[i][2] - d.b[i][2];\n" ++
    "        if (dh > 0) {\n" ++
    "          var core = d.b[i][1];\n" ++
    "          burst(t, core[3] / 1000, core[4] / 1000, Math.min(24, 4 + dh * 2), [255, 90, 70], 0.003);\n" ++
    "          texts[t].push({ x: core[3] / 1000, y: core[4] / 1000, age: 0, txt: '-' + dh, col: '#ff6a5a' });\n" ++
    "        }\n" ++
    "      }\n" ++
    "    }\n" ++
    "    st[t] = d;\n" ++
    "    for (i = 0; i < d.b.length; i++) {\n" ++
    "      var bd = d.b[i][1], B = d.b[i];\n" ++
    "      if (!trails[t][i]) trails[t][i] = [];\n" ++
    "      trails[t][i].push([bd[3] / 1000, bd[4] / 1000]); if (trails[t][i].length > 220) trails[t][i].shift();\n" ++
    "      /* bubbles from fins and the core while it swims */\n" ++
    "      var th = Math.abs(B[4]) / 100;\n" ++
    "      for (var ni = 0; ni < bd.length / 5; ni++) {\n" ++
    "        var ty = bd[ni * 5];\n" ++
    "        if ((ty === 3 && Math.random() < 0.25 * th) || (ty === 6 && Math.random() < 0.08 + 0.1 * th)) {\n" ++
    "          parts[t].push({ x: bd[ni * 5 + 3] / 1000, y: bd[ni * 5 + 4] / 1000, vx: (Math.random() - 0.5) * 0.0004, vy: -0.0002 - Math.random() * 0.0003, age: 0, life: 40 + Math.random() * 40, col: null, sz: Math.random() < 0.3 ? 2 : 1 });\n" ++
    "        }\n" ++
    "      }\n" ++
    "    }\n" ++
    "    if (parts[t].length > 400) parts[t].splice(0, parts[t].length - 400);\n" ++
    "  };\n" ++
    "  function burst(t, x, y, n, col, sp) {\n" ++
    "    for (var i = 0; i < n; i++) {\n" ++
    "      var a = Math.random() * 6.2832, v = sp * (0.3 + Math.random());\n" ++
    "      parts[t].push({ x: x, y: y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, age: 0, life: 22 + Math.random() * 22, col: col, sz: Math.random() < 0.4 ? 2 : 1 });\n" ++
    "    }\n" ++
    "  }\n" ++
    "  window.SwEvents.champ = function (d) { champ = d; drawChamp(); };\n" ++
    "  window.SwEvents.stats = function (d) {\n" ++
    "    stats = d;\n" ++
    "    var a = $('o-tr'); if (a) a.textContent = fmtc(d.trials);\n" ++
    "    var b = $('o-procs'); if (b) b.textContent = fmtc(d.procs);\n" ++
    "    poolTable(); charts();\n" ++
    "  };\n" ++
    "\n" ++
    "  /* ---------- pixel helpers (all drawing happens on a low-resolution buffer, then is scaled up crisp) ---------- */\n" ++
    "  var PX = 3;\n" ++
    "  var BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];\n" ++
    "  function h2(x, y) { var n = Math.imul(x, 374761393) + Math.imul(y, 668265263); n = Math.imul(n ^ (n >>> 13), 1274126177); return ((n ^ (n >>> 16)) >>> 0) / 4294967296; }\n" ++
    "  function vn(x, y) {\n" ++
    "    var xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);\n" ++
    "    var a = h2(xi, yi), b = h2(xi + 1, yi), c = h2(xi, yi + 1), e = h2(xi + 1, yi + 1);\n" ++
    "    return a + (b - a) * u + (c - a) * v + (a - b - c + e) * u * v;\n" ++
    "  }\n" ++
    "  function disc(g, cx, cy, r, c) {\n" ++
    "    cx = Math.round(cx); cy = Math.round(cy); var ri = Math.ceil(r); g.fillStyle = c;\n" ++
    "    for (var dy = -ri; dy <= ri; dy++) { var q = r * r - dy * dy; if (q < 0) continue; var w = Math.floor(Math.sqrt(q) + 0.35); g.fillRect(cx - w, cy + dy, 2 * w + 1, 1); }\n" ++
    "  }\n" ++
    "  function thick(g, a, b, r, c) {\n" ++
    "    var dx = b[0] - a[0], dy = b[1] - a[1], n = Math.max(1, Math.ceil(Math.sqrt(dx * dx + dy * dy)));\n" ++
    "    for (var i = 0; i <= n; i++) disc(g, a[0] + dx * i / n, a[1] + dy * i / n, r, c);\n" ++
    "  }\n" ++
    "  function ellipse(g, cx, cy, ux, uy, ra, rb, c) {\n" ++
    "    var R = Math.ceil(Math.max(ra, rb)); g.fillStyle = c;\n" ++
    "    for (var y = -R; y <= R; y++) for (var x = -R; x <= R; x++) {\n" ++
    "      var p = (x * ux + y * uy) / ra, q = (-x * uy + y * ux) / rb;\n" ++
    "      if (p * p + q * q <= 1) g.fillRect(Math.round(cx) + x, Math.round(cy) + y, 1, 1);\n" ++
    "    }\n" ++
    "  }\n" ++
    "  function tri(g, a, b, c, col) {\n" ++
    "    var x0 = Math.floor(Math.min(a[0], b[0], c[0])), x1 = Math.ceil(Math.max(a[0], b[0], c[0])), y0 = Math.floor(Math.min(a[1], b[1], c[1])), y1 = Math.ceil(Math.max(a[1], b[1], c[1]));\n" ++
    "    g.fillStyle = col;\n" ++
    "    var s = function (p, q, r) { return (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1]); };\n" ++
    "    for (var y = y0; y <= y1; y++) for (var x = x0; x <= x1; x++) {\n" ++
    "      var p = [x + 0.5, y + 0.5], d1 = s(p, a, b), d2 = s(p, b, c), d3 = s(p, c, a);\n" ++
    "      if (!((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))) g.fillRect(x, y, 1, 1);\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- a creature, in pixels. look = [x, y] it is looking at (eyes follow it), or null ---------- */\n" ++
    "  function drawCreature(g, bd, hue, P, s, look, now, bite) {\n" ++
    "    var n = P.length, i;\n" ++
    "    var rp = function (i) { return Math.max(1, bd[i * 5 + 1] / 10000 / WS * s); };\n" ++
    "    var OUT = hsl(hue, 60, 9), MID = hsl(hue, 55, 40), LIT = hsl(hue, 70, 62);\n" ++
    "    /* soft shadow on the floor */\n" ++
    "    for (i = 0; i < n; i++) if (bd[i * 5] !== 1) disc(g, P[i][0] + 2, P[i][1] + 3, rp(i) + 1, 'rgba(0,0,0,0.28)');\n" ++
    "    /* limbs: outline, fill, a lit ridge */\n" ++
    "    var lw = function (i) { var pi = bd[i * 5 + 2]; return Math.max(1, Math.min(rp(pi), rp(i)) * 0.5); };\n" ++
    "    for (i = 1; i < n; i++) { var pi = bd[i * 5 + 2]; if (pi >= 0 && pi < n) thick(g, P[pi], P[i], lw(i) + 1, OUT); }\n" ++
    "    for (i = 1; i < n; i++) { pi = bd[i * 5 + 2]; if (pi >= 0 && pi < n) thick(g, P[pi], P[i], lw(i), MID); }\n" ++
    "    for (i = 1; i < n; i++) { pi = bd[i * 5 + 2]; if (pi >= 0 && pi < n && lw(i) >= 1.5) thick(g, [P[pi][0] - 0.5, P[pi][1] - 0.5], [P[i][0] - 0.5, P[i][1] - 0.5], lw(i) * 0.35, LIT); }\n" ++
    "    var dirOf = function (i) {\n" ++
    "      var p2 = bd[i * 5 + 2]; if (i === 0 || p2 < 0 || p2 >= n) return [1, 0];\n" ++
    "      var lx = P[i][0] - P[p2][0], ly = P[i][1] - P[p2][1], ll = Math.sqrt(lx * lx + ly * ly) || 1; return [lx / ll, ly / ll];\n" ++
    "    };\n" ++
    "    /* fins first (they sit under everything) */\n" ++
    "    for (i = 0; i < n; i++) if (bd[i * 5] === 3) {\n" ++
    "      var u = dirOf(i), r = rp(i), fl = Math.sin(now / 140 + i) * 0.15;\n" ++
    "      ellipse(g, P[i][0], P[i][1], u[0], u[1], r * 2.4 + 1, r * (1.0 + fl) + 1, hsl(hue + 40, 70, 30, 0.9));\n" ++
    "      ellipse(g, P[i][0], P[i][1], u[0], u[1], r * 2.4, r * (1.0 + fl), hsl(hue + 40, 80, 64, 0.75));\n" ++
    "      ellipse(g, P[i][0] - u[0] * r * 0.6, P[i][1] - u[1] * r * 0.6, u[0], u[1], r * 1.2, r * 0.35, hsl(hue + 40, 90, 85, 0.6));\n" ++
    "    }\n" ++
    "    var order = [0, 2, 4, 5, 6];\n" ++
    "    for (var oi = 0; oi < order.length; oi++) {\n" ++
    "      var T = order[oi];\n" ++
    "      for (i = 0; i < n; i++) {\n" ++
    "        if (bd[i * 5] !== T) continue;\n" ++
    "        var x = P[i][0], y = P[i][1], R = rp(i);\n" ++
    "        if (T === 6 || T === 0) {\n" ++
    "          disc(g, x, y, R + 1, OUT);\n" ++
    "          disc(g, x, y, R, T === 6 ? hsl(hue, 60, 46) : hsl(hue, 55, 52));\n" ++
    "          disc(g, x - R * 0.3, y - R * 0.3, R * 0.55, T === 6 ? hsl(hue, 65, 58) : hsl(hue, 60, 64));\n" ++
    "          if (R >= 2) g.fillStyle = hsl(hue, 80, 88), g.fillRect(Math.round(x - R * 0.5), Math.round(y - R * 0.5), 1, 1);\n" ++
    "          if (T === 6) disc(g, x + R * 0.1, y + R * 0.1, R * 0.32, hsl(hue + 180, 45, 22));\n" ++
    "        } else if (T === 2) {\n" ++
    "          disc(g, x, y, R + 1, '#151b26');\n" ++
    "          disc(g, x, y, R, '#7d899c');\n" ++
    "          disc(g, x - R * 0.25, y - R * 0.25, R * 0.6, '#aab6c8');\n" ++
    "          g.fillStyle = '#4a5466'; g.fillRect(Math.round(x - R), Math.round(y), Math.round(2 * R) + 1, 1); g.fillRect(Math.round(x), Math.round(y - R), 1, Math.round(2 * R) + 1);\n" ++
    "        } else if (T === 4) {\n" ++
    "          disc(g, x, y, R + 1, '#2a0508');\n" ++
    "          disc(g, x, y, R, '#8a1c26');\n" ++
    "          var open = bite > 0.3 ? 0.62 + 0.15 * Math.sin(now / 60) : 0.45;\n" ++
    "          disc(g, x, y, R * open, '#120306');\n" ++
    "          var nt = Math.max(4, Math.round(R * 2.2)), rot = now / 900;\n" ++
    "          g.fillStyle = '#f6f0e4';\n" ++
    "          for (var k = 0; k < nt; k++) { var a = rot + k * 6.2832 / nt; g.fillRect(Math.round(x + Math.cos(a) * R * (open + 0.12)), Math.round(y + Math.sin(a) * R * (open + 0.12)), 1, 1); }\n" ++
    "        } else if (T === 5) {\n" ++
    "          disc(g, x, y, R + 1, '#141a26');\n" ++
    "          disc(g, x, y, R, '#eef3ff');\n" ++
    "          var lx = 0, ly = 0;\n" ++
    "          if (look) { var ex = look[0] - x, ey = look[1] - y, el = Math.sqrt(ex * ex + ey * ey) || 1; lx = ex / el; ly = ey / el; }\n" ++
    "          disc(g, x + lx * R * 0.38, y + ly * R * 0.38, Math.max(0.6, R * 0.48), '#05060a');\n" ++
    "          g.fillStyle = '#ffffff'; g.fillRect(Math.round(x - R * 0.4), Math.round(y - R * 0.45), 1, 1);\n" ++
    "        }\n" ++
    "      }\n" ++
    "    }\n" ++
    "    /* spikes on top: blades pointing out along their limb */\n" ++
    "    for (i = 0; i < n; i++) if (bd[i * 5] === 1) {\n" ++
    "      var d = dirOf(i), R2 = rp(i) + 0.5, nx = -d[1], ny = d[0], bx = P[i][0], by = P[i][1];\n" ++
    "      var tip = [bx + d[0] * R2 * 3.0, by + d[1] * R2 * 3.0];\n" ++
    "      tri(g, [bx + nx * (R2 + 1), by + ny * (R2 + 1)], [tip[0] + d[0], tip[1] + d[1]], [bx - nx * (R2 + 1), by - ny * (R2 + 1)], '#3a0a0e');\n" ++
    "      tri(g, [bx + nx * R2, by + ny * R2], tip, [bx - nx * R2, by - ny * R2], '#d8323c');\n" ++
    "      tri(g, [bx + nx * R2 * 0.3, by + ny * R2 * 0.3], tip, [bx, by], '#ff7a6e');\n" ++
    "      g.fillStyle = '#fff1e8'; g.fillRect(Math.round(tip[0]), Math.round(tip[1]), 1, 1);\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- backgrounds: one look per task, computed per pixel in world coordinates so the camera moves through them ---------- */\n" ++
    "  var PAL = [\n" ++
    "    [[2, 5, 12], [5, 12, 26], [9, 22, 42], [15, 36, 62], [24, 54, 86]],          /* abyss */\n" ++
    ""
}

fun part1() {
    "    [[3, 20, 24], [6, 34, 38], [11, 52, 54], [20, 74, 70], [38, 104, 92]],        /* reef */\n" ++
    "    [[14, 6, 8], [26, 11, 14], [40, 18, 20], [58, 28, 26], [80, 42, 34]]          /* pit */\n" ++
    "  ];\n" ++
    "  function background(t, b, cam, s, now, d) {\n" ++
    "    var W = b.w, H = b.h, data = b.u32, pal = PAL[t], i = 0;\n" ++
    "    var tgx = -1e9, tgy = -1e9, LR = 0.075 * s;\n" ++
    "    if (t === 0 && d && d.tg) { tgx = W / 2 + (d.tg[0] / 1000 - cam[0]) * s; tgy = H / 2 + (d.tg[1] / 1000 - cam[1]) * s; }\n" ++
    "    var tt = now * 0.00025;\n" ++
    "    for (var y = 0; y < H; y++) {\n" ++
    "      var v = cam[1] + (y - H / 2) / s;\n" ++
    "      for (var x = 0; x < W; x++, i++) {\n" ++
    "        var u = cam[0] + (x - W / 2) / s, val, light = 0, rim = 0;\n" ++
    "        var bay = BAYER[(y & 3) * 4 + (x & 3)] / 16 - 0.5;\n" ++
    "        if (t === 0) {\n" ++
    "          val = 0.18 + 0.42 * vn(u * 38, v * 38) + 0.18 * vn(u * 120 + tt * 8, v * 120);\n" ++
    "          var dx = x - tgx, dy = y - tgy; light = Math.exp(-(dx * dx + dy * dy) / (LR * LR));\n" ++
    "          val += light * 0.9;\n" ++
    "        } else if (t === 1) {\n" ++
    "          val = 0.25 + 0.35 * vn(u * 30, v * 30);\n" ++
    "          var c = vn(u * 70 + tt * 6, v * 70 - tt * 4); if (c > 0.68) val += (c - 0.68) * 2.6;\n" ++
    "          if (h2(Math.floor(u * 900), Math.floor(v * 900)) > 0.985) val += 0.35;\n" ++
    "        } else {\n" ++
    "          var cx = u - 0.5, cy = v - 0.5, r = Math.sqrt(cx * cx + cy * cy);\n" ++
    "          if (r < 0.16) {\n" ++
    "            var gu = (u * 45) % 1, gv = (v * 45) % 1;\n" ++
    "            val = 0.42 + 0.22 * vn(u * 60, v * 60) - ((gu < 0.07 || gv < 0.07) ? 0.25 : 0);\n" ++
    "            if (vn(u * 25, v * 25) > 0.72 && h2(Math.floor(u * 400), Math.floor(v * 400)) > 0.6) val -= 0.2;\n" ++
    "          } else if (r < 0.168) { rim = 1; val = 0.9; }\n" ++
    "          else { val = 0.12 + 0.3 * vn(u * 22, v * 22); }\n" ++
    "        }\n" ++
    "        var lv = val + bay * 0.22, k = lv < 0.2 ? 0 : lv < 0.4 ? 1 : lv < 0.6 ? 2 : lv < 0.8 ? 3 : 4, col = pal[k];\n" ++
    "        var R = col[0], G = col[1], B = col[2];\n" ++
    "        if (t === 0 && light > 0.04) {\n" ++
    "          var lq = Math.min(1, light + bay * 0.25);\n" ++
    "          var w = lq > 0.75 ? 0.75 : lq > 0.45 ? 0.45 : lq > 0.2 ? 0.2 : 0;\n" ++
    "          R = R + (255 - R) * w * 0.85; G = G + (200 - G) * w * 0.7; B = B + (90 - B) * w * 0.35;\n" ++
    "        }\n" ++
    "        if (t === 2 && rim) { var pulse = 0.6 + 0.4 * Math.sin(now / 300 + u * 40); R = 200 * pulse + 40; G = 70 * pulse + 20; B = 40; }\n" ++
    "        data[i] = 0xff000000 | (B << 16) | (G << 8) | (R | 0);\n" ++
    "      }\n" ++
    "    }\n" ++
    "    b.g.putImageData(b.img, 0, 0);\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- prey and pellet sprites ---------- */\n" ++
    "  function drawPellet(g, x, y, now) {\n" ++
    "    var p = Math.sin(now / 200);\n" ++
    "    disc(g, x, y, 4 + (p > 0.3 ? 1 : 0), '#6a4a12');\n" ++
    "    disc(g, x, y, 3 + (p > 0.3 ? 1 : 0), '#ffc24a');\n" ++
    "    disc(g, x, y, 2, '#ffe9a8');\n" ++
    "    g.fillStyle = '#ffffff'; g.fillRect(Math.round(x) - 1, Math.round(y) - 1, 1, 1);\n" ++
    "    var a = now / 500;\n" ++
    "    g.fillStyle = '#fff3c4';\n" ++
    "    for (var k = 0; k < 4; k++) { var aa = a + k * 1.5708; g.fillRect(Math.round(x + Math.cos(aa) * 8), Math.round(y + Math.sin(aa) * 8), 1, 1); }\n" ++
    "  }\n" ++
    "  function drawShrimp(g, x, y, hx, hy, now) {\n" ++
    "    var nx = -hy, ny = hx, segs = 6, wig = Math.sin(now / 70);\n" ++
    "    for (var k = segs - 1; k >= 0; k--) {\n" ++
    "      var off = k * 1.6, bend = Math.sin(now / 90 - k * 0.7) * 0.6 * (k / segs);\n" ++
    "      var sx = x - hx * off + nx * bend, sy = y - hy * off + ny * bend, r = k === 0 ? 2.2 : 2.6 - k * 0.3;\n" ++
    "      disc(g, sx, sy, r + 1, '#4a1410');\n" ++
    "      disc(g, sx, sy, r, k % 2 ? '#ff8a6a' : '#ffa889');\n" ++
    "    }\n" ++
    "    var tx = x - hx * segs * 1.6, ty = y - hy * segs * 1.6;\n" ++
    "    tri(g, [tx, ty], [tx - hx * 4 + nx * (3 + wig), ty - hy * 4 + ny * (3 + wig)], [tx - hx * 4 - nx * (3 - wig), ty - hy * 4 - ny * (3 - wig)], '#ff6f55');\n" ++
    "    g.fillStyle = '#05060a'; g.fillRect(Math.round(x + hx * 1 + nx * 1.2), Math.round(y + hy * 1 + ny * 1.2), 1, 1);\n" ++
    "    g.fillStyle = '#ffd0c0';\n" ++
    "    for (var a = 1; a <= 7; a++) { g.fillRect(Math.round(x + hx * (2 + a) + nx * (a * 0.5 + wig * 0.3)), Math.round(y + hy * (2 + a) + ny * (a * 0.5 + wig * 0.3)), 1, 1); g.fillRect(Math.round(x + hx * (2 + a) - nx * (a * 0.5 - wig * 0.3)), Math.round(y + hy * (2 + a) - ny * (a * 0.5 - wig * 0.3)), 1, 1); }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- one task view ---------- */\n" ++
    "  var bufs = [null, null, null];\n" ++
    "  function getBuf(t, w, h) {\n" ++
    "    var b = bufs[t];\n" ++
    "    if (!b || b.w !== w || b.h !== h) {\n" ++
    "      var cv = document.createElement('canvas'); cv.width = w; cv.height = h;\n" ++
    "      var g = cv.getContext('2d'), img = g.createImageData(w, h);\n" ++
    "      b = bufs[t] = { cv: cv, g: g, w: w, h: h, img: img, u32: new Uint32Array(img.data.buffer) };\n" ++
    "    }\n" ++
    "    return b;\n" ++
    "  }\n" ++
    "  function fitCanvas(i) {\n" ++
    "    var cv = $('tc' + i); if (!cv) return null;\n" ++
    "    var w = cv.clientWidth, h = cv.clientHeight;\n" ++
    "    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }\n" ++
    "    var g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    return { g: g, w: w, h: h };\n" ++
    "  }\n" ++
    "  function drawTask(t, now) {\n" ++
    "    var c = fitCanvas(t); if (!c) return;\n" ++
    "    var G = c.g, W = c.w, H = c.h, d = st[t];\n" ++
    "    var bw = Math.ceil(W / PX), bh = Math.ceil(H / PX), b = getBuf(t, bw, bh), g = b.g;\n" ++
    "    /* the camera frames every body and the target, zooming smoothly */\n" ++
    "    var mnx = 0.5, mny = 0.5, mxx = 0.5, mxy = 0.5, q, bb;\n" ++
    "    if (d && d.b.length) {\n" ++
    "      mnx = 1e9; mny = 1e9; mxx = -1e9; mxy = -1e9;\n" ++
    "      for (q = 0; q < d.b.length; q++) { bb = d.b[q][1]; for (var ni = 0; ni < bb.length / 5; ni++) { var ux = bb[ni * 5 + 3] / 1000, uy = bb[ni * 5 + 4] / 1000; mnx = Math.min(mnx, ux); mxx = Math.max(mxx, ux); mny = Math.min(mny, uy); mxy = Math.max(mxy, uy); } }\n" ++
    "      if (d.tg) { mnx = Math.min(mnx, d.tg[0] / 1000); mxx = Math.max(mxx, d.tg[0] / 1000); mny = Math.min(mny, d.tg[1] / 1000); mxy = Math.max(mxy, d.tg[1] / 1000); }\n" ++
    "    }\n" ++
    "    var cx = (mnx + mxx) / 2, cy = (mny + mxy) / 2, want = clamp(Math.max((mxx - mnx) * bw / Math.min(bw, bh), (mxy - mny) * bh / Math.min(bw, bh)) * 1.5 + 0.06, 0.16, 0.6);\n" ++
    "    if (!cams[t]) cams[t] = [cx, cy, want];\n" ++
    "    cams[t][0] += (cx - cams[t][0]) * 0.06; cams[t][1] += (cy - cams[t][1]) * 0.06; cams[t][2] += (want - cams[t][2]) * 0.03;\n" ++
    "    var s = Math.min(bw, bh) / cams[t][2];\n" ++
    "    var cam = [Math.round(cams[t][0] * s) / s, Math.round(cams[t][1] * s) / s];\n" ++
    "    var SX = function (u) { return bw / 2 + (u - cam[0]) * s; }, SY = function (v) { return bh / 2 + (v - cam[1]) * s; };\n" ++
    "    background(t, b, cam, s, now, d);\n" ++
    "    if (d && d.b.length) {\n" ++
    "      /* the path it swam: a dotted wake */\n" ++
    "      for (var bi = 0; bi < trails[t].length; bi++) {\n" ++
    "        var tr = trails[t][bi]; if (!tr) continue;\n" ++
    "        var hue = d.b[bi] ? d.b[bi][0] : 180;\n" ++
    "        for (var i = tr.length - 1; i >= 0; i -= 3) { var a = i / tr.length; g.fillStyle = hsl(hue, 70, 70, 0.08 + 0.3 * a); g.fillRect(Math.round(SX(tr[i][0])), Math.round(SY(tr[i][1])), 1, 1); }\n" ++
    "      }\n" ++
    "      /* target */\n" ++
    "      var look = null;\n" ++
    "      if (d.tg) {\n" ++
    "        var tx = SX(d.tg[0] / 1000), ty = SY(d.tg[1] / 1000); look = [tx, ty];\n" ++
    "        if (t === 0) drawPellet(g, tx, ty, now);\n" ++
    "        else {\n" ++
    "          var hx = 1, hy = 0;\n" ++
    "          if (preyPrev) { var mx = d.tg[0] - preyPrev[0], my = d.tg[1] - preyPrev[1], ml = Math.sqrt(mx * mx + my * my); if (ml > 0.5) { hx = mx / ml; hy = my / ml; } else { hx = preyPrev[2]; hy = preyPrev[3]; } }\n" ++
    "          preyPrev = [d.tg[0], d.tg[1], hx, hy];\n" ++
    "          drawShrimp(g, tx, ty, hx, hy, now);\n" ++
    "        }\n" ++
    "      }\n" ++
    "      /* bodies */\n" ++
    "      for (bi = 0; bi < d.b.length; bi++) {\n" ++
    "        var B = d.b[bi], bd = B[1], P = [];\n" ++
    "        for (i = 0; i < bd.length / 5; i++) P.push([SX(bd[i * 5 + 3] / 1000), SY(bd[i * 5 + 4] / 1000)]);\n" ++
    "        var lk = look;\n" ++
    "        if (t === 2 && d.b.length > 1) { var o = d.b[1 - bi][1]; lk = [SX(o[3] / 1000), SY(o[4] / 1000)]; }\n" ++
    "        drawCreature(g, bd, B[0], P, s, lk, now, B[6] / 100);\n" ++
    "      }\n" ++
    "      /* particles: bubbles rise and fade, bursts fly out */\n" ++
    "      var ps = parts[t];\n" ++
    "      for (i = 0; i < ps.length; i++) {\n" ++
    "        var p = ps[i]; p.age++; p.x += p.vx; p.y += p.vy; p.vx *= 0.94; p.vy *= 0.94; if (!p.col) p.vy -= 0.00001;\n" ++
    "        var f = 1 - p.age / p.life; if (f <= 0) continue;\n" ++
    "        var px = Math.round(SX(p.x)), py = Math.round(SY(p.y));\n" ++
    "        if (p.col) { g.fillStyle = 'rgba(' + p.col[0] + ',' + p.col[1] + ',' + p.col[2] + ',' + f + ')'; g.fillRect(px, py, p.sz, p.sz); }\n" ++
    "        else { g.fillStyle = 'rgba(190,230,255,' + (0.55 * f) + ')'; if (p.sz > 1) { g.fillRect(px - 1, py, 3, 1); g.fillRect(px, py - 1, 1, 3); } else g.fillRect(px, py, 1, 1); }\n" ++
    "      }\n" ++
    "      parts[t] = ps.filter(function (p) { return p.age < p.life; });\n" ++
    "      /* rings where something was caught */\n" ++
    "      for (i = 0; i < rings[t].length; i++) {\n" ++
    "        var rg = rings[t][i]; rg.age++; var rr = rg.age * 0.7, al = 1 - rg.age / 30; if (al <= 0) continue;\n" ++
    "        var rx = SX(rg.x), ry = SY(rg.y); g.fillStyle = 'rgba(' + rg.col[0] + ',' + rg.col[1] + ',' + rg.col[2] + ',' + al + ')';\n" ++
    "        for (var k = 0; k < 24; k++) { var aa = k * 0.2618; g.fillRect(Math.round(rx + Math.cos(aa) * rr), Math.round(ry + Math.sin(aa) * rr), 1, 1); }\n" ++
    "      }\n" ++
    "      rings[t] = rings[t].filter(function (r) { return r.age < 30; });\n" ++
    "    }\n" ++
    "    /* scale the pixels up */\n" ++
    "    G.imageSmoothingEnabled = false;\n" ++
    "    G.drawImage(b.cv, 0, 0, bw * PX, bh * PX);\n" ++
    "    /* bloom over the pixels (full resolution, additive) */\n" ++
    "    G.globalCompositeOperation = 'lighter';\n" ++
    "    if (d && d.tg) {\n" ++
    "      var gx = SX(d.tg[0] / 1000) * PX, gy = SY(d.tg[1] / 1000) * PX, R0 = t === 0 ? 70 + 8 * Math.sin(now / 200) : 30;\n" ++
    "      var gr = G.createRadialGradient(gx, gy, 0, gx, gy, R0); gr.addColorStop(0, t === 0 ? 'rgba(255,200,90,0.45)' : 'rgba(255,140,110,0.22)'); gr.addColorStop(1, 'rgba(0,0,0,0)');\n" ++
    "      G.fillStyle = gr; G.fillRect(gx - R0, gy - R0, R0 * 2, R0 * 2);\n" ++
    "    }\n" ++
    "    if (t === 2 && d) for (bi = 0; bi < d.b.length; bi++) if (d.b[bi][3] > 0) {\n" ++
    "      var cb = d.b[bi][1], hx2 = SX(cb[3] / 1000) * PX, hy2 = SY(cb[4] / 1000) * PX, R1 = 50;\n" ++
    "      var gr2 = G.createRadialGradient(hx2, hy2, 0, hx2, hy2, R1); gr2.addColorStop(0, 'rgba(255,60,40,' + (0.05 * d.b[bi][3]) + ')'); gr2.addColorStop(1, 'rgba(0,0,0,0)');\n" ++
    "      G.fillStyle = gr2; G.fillRect(hx2 - R1, hy2 - R1, R1 * 2, R1 * 2);\n" ++
    "    }\n" ++
    "    G.globalCompositeOperation = 'source-over';\n" ++
    "    /* vignette */\n" ++
    "    var vg = G.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.35, W / 2, H / 2, Math.max(W, H) * 0.75);\n" ++
    "    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, t === 2 ? 'rgba(20,0,0,0.6)' : 'rgba(0,0,0,0.6)');\n" ++
    "    G.fillStyle = vg; G.fillRect(0, 0, W, H);\n" ++
    "    if (!d || !d.b.length) { G.fillStyle = '#8f8f8f'; G.font = '13px ui-sans-serif,-apple-system,sans-serif'; G.textAlign = 'center'; G.fillText('waiting for a champion', W / 2, H / 2); return; }\n" ++
    "    /* floating text and labels, crisp at full resolution */\n" ++
    "    G.textAlign = 'center';\n" ++
    "    for (i = 0; i < texts[t].length; i++) {\n" ++
    "      var tx2 = texts[t][i]; tx2.age++; var al2 = 1 - tx2.age / 50; if (al2 <= 0) continue;\n" ++
    "      G.globalAlpha = al2; G.font = '700 13px ui-sans-serif,-apple-system,sans-serif';\n" ++
    "      G.fillStyle = '#000'; G.fillText(tx2.txt, SX(tx2.x) * PX + 1, SY(tx2.y) * PX - 14 - tx2.age * 0.6 + 1);\n" ++
    "      G.fillStyle = tx2.col; G.fillText(tx2.txt, SX(tx2.x) * PX, SY(tx2.y) * PX - 14 - tx2.age * 0.6);\n" ++
    "    }\n" ++
    "    G.globalAlpha = 1;\n" ++
    "    texts[t] = texts[t].filter(function (x) { return x.age < 50; });\n" ++
    "    if (t === 2) for (bi = 0; bi < d.b.length; bi++) {\n" ++
    "      var Bf = d.b[bi], cbf = Bf[1], fx = SX(cbf[3] / 1000) * PX, fy = SY(cbf[4] / 1000) * PX - 46, hp = clamp(Bf[2] / 100, 0, 1);\n" ++
    "      G.fillStyle = 'rgba(0,0,0,0.7)'; G.fillRect(fx - 26, fy - 1, 52, 8);\n" ++
    "      for (var sg = 0; sg < 10; sg++) { G.fillStyle = sg < Math.ceil(hp * 10) ? (hp > 0.5 ? '#50e3c2' : hp > 0.25 ? '#f5a623' : '#ff5a5a') : '#2a2a2a'; G.fillRect(fx - 25 + sg * 5, fy, 4, 6); }\n" ++
    "      G.font = '700 11px ui-sans-serif,-apple-system,sans-serif'; G.fillStyle = bi === 0 ? '#ffd36b' : '#c9c9c9'; G.fillText(bi === 0 ? 'CHAMPION' : 'RUNNER-UP', fx, fy - 6);\n" ++
    "    }\n" ++
    "    /* off-screen target arrow */\n" ++
    "    if (d.tg) {\n" ++
    "      var ax = SX(d.tg[0] / 1000) * PX, ay = SY(d.tg[1] / 1000) * PX;\n" ++
    "      if (ax < 0 || ax > W || ay < 0 || ay > H) {\n" ++
    "        var ang = Math.atan2(ay - H / 2, ax - W / 2), qx = clamp(ax, 18, W - 18), qy = clamp(ay, 70, H - 18);\n" ++
    "        G.save(); G.translate(qx, qy); G.rotate(ang); G.fillStyle = t === 0 ? '#ffd36b' : '#ff9e7a';\n" ++
    "        G.beginPath(); G.moveTo(10, 0); G.lineTo(-6, -7); G.lineTo(-6, 7); G.closePath(); G.fill(); G.restore();\n" ++
    "      }\n" ++
    "    }\n" ++
    "    var o2 = d.b[0];\n" ++
    "    G.textAlign = 'left'; G.fillStyle = 'rgba(200,200,200,0.85)'; G.font = '11px ui-monospace,SFMono-Regular,Menlo,monospace';\n" ++
    "    G.fillText('THRUST ' + bar(o2[4] / 100) + '  TURN ' + (o2[5] >= 0 ? '+' : '') + (o2[5] / 100).toFixed(2) + (t === 2 ? '  BITE ' + bar(o2[6] / 100) : ''), 14, H - 14);\n" ++
    ""
}

fun part2() {
    "    var sc = $('ts' + t); if (sc) sc.textContent = t === 2 ? (d.sc / 100).toFixed(1) : String(d.n);\n" ++
    "    var pb = $('tp' + t); if (pb) pb.style.width = Math.round(100 * d.tick / d.T) + '%';\n" ++
    "  }\n" ++
    "  function bar(v) { var k = Math.round(clamp(v, 0, 1) * 6), s = ''; for (var i = 0; i < 6; i++) s += i < k ? '|' : '.'; return s; }\n" ++
    "\n" ++
    "  /* ---------- the champion portrait ---------- */\n" ++
    "  var cbuf = null;\n" ++
    "  function drawChamp() {\n" ++
    "    if (!champ) return;\n" ++
    "    var cv = $('c-cv'); if (!cv) return;\n" ++
    "    var G = cv.getContext('2d'), W = cv.width, H = cv.height, B = champ.body[0], bd = B[1], n = bd.length / 5, i;\n" ++
    "    var bw = 80, bh = 80;\n" ++
    "    if (!cbuf) { var c2 = document.createElement('canvas'); c2.width = bw; c2.height = bh; cbuf = { cv: c2, g: c2.getContext('2d') }; }\n" ++
    "    var g = cbuf.g;\n" ++
    "    var gr = g.createRadialGradient(bw / 2, bh / 2, 4, bw / 2, bh / 2, bw * 0.7); gr.addColorStop(0, '#10233a'); gr.addColorStop(1, '#03060c');\n" ++
    "    g.fillStyle = gr; g.fillRect(0, 0, bw, bh);\n" ++
    "    var mnx = 1e9, mny = 1e9, mxx = -1e9, mxy = -1e9;\n" ++
    "    for (i = 0; i < n; i++) { var x = bd[i * 5 + 3], y = bd[i * 5 + 4]; mnx = Math.min(mnx, x); mxx = Math.max(mxx, x); mny = Math.min(mny, y); mxy = Math.max(mxy, y); }\n" ++
    "    var span = Math.max(mxx - mnx, mxy - mny, 20) / 1000, s = bw * 0.6 / span, P = [];\n" ++
    "    for (i = 0; i < n; i++) P.push([bw / 2 + ((bd[i * 5 + 3] - (mnx + mxx) / 2) / 1000) * s, bh / 2 + ((bd[i * 5 + 4] - (mny + mxy) / 2) / 1000) * s]);\n" ++
    "    drawCreature(g, bd, B[0], P, s, [bw / 2 + 20, bh / 2], performance.now(), 0);\n" ++
    "    G.imageSmoothingEnabled = false; G.clearRect(0, 0, W, H); G.drawImage(cbuf.cv, 0, 0, W, H);\n" ++
    "    var cnt = [0, 0, 0, 0, 0, 0, 0]; for (i = 0; i < n; i++) cnt[bd[i * 5]]++;\n" ++
    "    $('c-title').textContent = 'Pool ' + (champ.k + 1) + ' champion';\n" ++
    "    $('c-st').textContent = 'genome #' + champ.id + ' · lineage generation ' + fmtc(champ.gen);\n" ++
    "    $('c-sub').textContent = 'running its three trials live';\n" ++
    "    var kv = [['light', (champ.sc[0] / 100).toFixed(2)], ['chase', (champ.sc[1] / 100).toFixed(2)], ['fight', (champ.sc[2] / 100).toFixed(1)],\n" ++
    "      ['neurons', champ.nn], ['synapses', champ.nc], ['body parts', n],\n" ++
    "      ['fins', cnt[3]], ['spikes', cnt[1]], ['mouths', cnt[4]]];\n" ++
    "    $('c-kv').innerHTML = kv.map(function (x) { return '<div>' + x[0] + '<b>' + x[1] + '</b></div>'; }).join('');\n" ++
    "  }\n" ++
    "\n" ++
    "  function poolTable() {\n" ++
    "    var el = $('pt'); if (!el || !stats) return;\n" ++
    "    var show = stats.show && stats.show.length ? stats.show[0] : -1;\n" ++
    "    var h = '<tr><th>pool</th><th>generation</th><th>best light</th><th>best chase</th><th>best fight</th><th>mean light</th><th>mean chase</th><th>mean fight</th><th>s / gen</th></tr>';\n" ++
    "    stats.pools.forEach(function (p) {\n" ++
    "      var l = p[3] || [];\n" ++
    "      h += '<tr class=\"' + (p[0] === show ? 'on' : '') + '\"><td>Pool ' + (p[0] + 1) + '</td><td>' + fmtc(p[1]) + '</td>' +\n" ++
    "        (l.length ? '<td>' + (l[1] / 100).toFixed(2) + '</td><td>' + (l[2] / 100).toFixed(2) + '</td><td>' + (l[3] / 100).toFixed(1) + '</td><td>' + (l[4] / 100).toFixed(2) + '</td><td>' + (l[5] / 100).toFixed(2) + '</td><td>' + (l[6] / 100).toFixed(1) + '</td>' : '<td colspan=\"6\" style=\"text-align:left;color:#5f5f5f\">first generation running</td>') +\n" ++
    "        '<td>' + (p[4] ? (p[4] / 1000).toFixed(1) : '&ndash;') + '</td></tr>';\n" ++
    "    });\n" ++
    "    el.innerHTML = h;\n" ++
    "  }\n" ++
    "  function charts() {\n" ++
    "    if (!stats) return;\n" ++
    "    for (var t = 0; t < 3; t++) {\n" ++
    "      var cv = $('ch' + t); if (!cv) continue;\n" ++
    "      var w = cv.clientWidth, h = cv.clientHeight; cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);\n" ++
    "      var g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, w, h);\n" ++
    "      var lo = 1e9, hi = -1e9, g0 = 1e9, g1 = -1e9, series = [];\n" ++
    "      stats.hist.forEach(function (rows, k) {\n" ++
    "        var r = rows.slice().reverse(); series.push(r);\n" ++
    "        r.forEach(function (x) { var v = x[1 + t] / 100; lo = Math.min(lo, v); hi = Math.max(hi, v); g0 = Math.min(g0, x[0]); g1 = Math.max(g1, x[0]); });\n" ++
    "      });\n" ++
    "      if (hi < lo) continue; if (hi - lo < 0.01) hi = lo + 0.01; if (g1 <= g0) g1 = g0 + 1;\n" ++
    "      var X = function (gn) { return 2 + (gn - g0) / (g1 - g0) * (w - 40); }, Y = function (v) { return h - 14 - (v - lo) / (hi - lo) * (h - 22); };\n" ++
    "      g.strokeStyle = '#1c1c1c'; g.lineWidth = 1; g.beginPath(); g.moveTo(0, h - 14); g.lineTo(w, h - 14); g.stroke();\n" ++
    "      series.forEach(function (r, k) {\n" ++
    "        if (r.length < 2) return;\n" ++
    "        g.strokeStyle = hsl(k * 47 + 20, 70, 60, 0.85); g.lineWidth = 1.5; g.beginPath();\n" ++
    "        r.forEach(function (x, i) { var px = X(x[0]), py = Y(x[1 + t] / 100); if (i) g.lineTo(px, py); else g.moveTo(px, py); });\n" ++
    "        g.stroke();\n" ++
    "      });\n" ++
    "      g.fillStyle = '#8f8f8f'; g.font = '10px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'right';\n" ++
    "      g.fillText(hi.toFixed(t === 2 ? 0 : 1), w - 2, 10); g.fillText(lo.toFixed(t === 2 ? 0 : 1), w - 2, h - 16);\n" ++
    "      g.textAlign = 'left'; g.fillText('gen ' + g0, 2, h - 2); g.textAlign = 'right'; g.fillText('gen ' + g1, w - 38, h - 2);\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  var lastDraw = 0;\n" ++
    "  function frame(now) {\n" ++
    "    build();\n" ++
    "    if (now - lastDraw > 30) { lastDraw = now; for (var t = 0; t < 3; t++) drawTask(t, now); }\n" ++
    "    requestAnimationFrame(frame);\n" ++
    "  }\n" ++
    "  requestAnimationFrame(frame);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
