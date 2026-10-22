module Evolve4ArenaJs

# GENERATED from src/evolve4_arena.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() { part0() ++ part1() }

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
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  window.SwEvents.live = function (d) {\n" ++
    "    var t = d.task;\n" ++
    "    if (!st[t] || d.tick < st[t].tick) { trails[t] = []; cams[t] = null; if (t === 1) preyPrev = null; }\n" ++
    "    st[t] = d;\n" ++
    "    for (var i = 0; i < d.b.length; i++) {\n" ++
    "      var bd = d.b[i][1];\n" ++
    "      if (!trails[t][i]) trails[t][i] = [];\n" ++
    "      trails[t][i].push([bd[3] / 1000, bd[4] / 1000]); if (trails[t][i].length > 160) trails[t][i].shift();\n" ++
    "    }\n" ++
    "  };\n" ++
    "  window.SwEvents.champ = function (d) { champ = d; drawChamp(); };\n" ++
    "  window.SwEvents.stats = function (d) {\n" ++
    "    stats = d;\n" ++
    "    var a = $('o-tr'); if (a) a.textContent = fmtc(d.trials);\n" ++
    "    var b = $('o-procs'); if (b) b.textContent = fmtc(d.procs);\n" ++
    "    poolTable(); charts();\n" ++
    "  };\n" ++
    "\n" ++
    "  /* ---------- drawing a body ---------- */\n" ++
    "  var nspr = {};\n" ++
    "  function nodeSprite(type, hue, R) {\n" ++
    "    var key = type + ':' + Math.round(hue / 10) + ':' + R;\n" ++
    "    if (nspr[key]) return nspr[key];\n" ++
    "    var D = R * 2 + 2, cv = document.createElement('canvas'); cv.width = D; cv.height = D;\n" ++
    "    var g = cv.getContext('2d'), c0 = D / 2;\n" ++
    "    for (var y = 0; y < D; y++) for (var x = 0; x < D; x++) {\n" ++
    "      var dx = x + 0.5 - c0, dy = y + 0.5 - c0, dd = Math.sqrt(dx * dx + dy * dy);\n" ++
    "      if (dd > R) continue;\n" ++
    "      var edge = dd > R - 1.1, light = (-dx - dy) / (R * 1.4), col;\n" ++
    "      if (type === 6 || type === 0) {\n" ++
    "        col = edge ? hsl(hue, 70, 20) : hsl(hue, 60, (type === 6 ? 48 : 58) + light * 16);\n" ++
    "        if (type === 6 && dd < Math.max(1, R * 0.35)) col = hsl(hue + 180, 35, 22);\n" ++
    "      } else if (type === 2) {\n" ++
    "        var seg = Math.floor((Math.atan2(dy, dx) + 3.1416) / 0.8) % 2;\n" ++
    "        col = edge ? '#4a5262' : (seg ? '#b9c4d4' : '#8c98ab');\n" ++
    "      } else if (type === 4) {\n" ++
    "        col = edge ? (((x + y) & 1) ? '#f4f0e8' : '#3a0a10') : (dd < R * 0.5 ? '#14040a' : '#7a1822');\n" ++
    "      } else if (type === 5) {\n" ++
    "        col = dd < Math.max(1, R * 0.45) ? '#05060a' : (edge ? '#9aa4b8' : '#f2f6ff');\n" ++
    "      } else { col = hsl(hue, 60, 55); }\n" ++
    "      g.fillStyle = col; g.fillRect(x, y, 1, 1);\n" ++
    "    }\n" ++
    "    return (nspr[key] = cv);\n" ++
    "  }\n" ++
    "  function pixelLine(g, a, b, w, col) {\n" ++
    "    var dx = b[0] - a[0], dy = b[1] - a[1], d = Math.sqrt(dx * dx + dy * dy), n = Math.max(1, Math.ceil(d / Math.max(1, w * 0.6)));\n" ++
    "    g.fillStyle = col;\n" ++
    "    for (var i = 0; i <= n; i++) { var u = i / n; g.fillRect(a[0] + dx * u - w / 2, a[1] + dy * u - w / 2, w, w); }\n" ++
    "  }\n" ++
    "  /* bd: flat body, P: screen points, s: pixels per world-thousandth-normalised unit, k: pixel size */\n" ++
    "  function drawMesh(g, bd, hue, P, s, k) {\n" ++
    "    var n = P.length, i;\n" ++
    "    var rp = function (i) { return bd[i * 5 + 1] / 10000 / WS * s; };\n" ++
    "    g.fillStyle = hsl(hue, 60, 50, 0.16);\n" ++
    "    for (i = 0; i < n; i++) { if (bd[i * 5] === 1) continue; g.beginPath(); g.arc(P[i][0], P[i][1], Math.max(k, rp(i)) * 1.9, 0, 6.2832); g.fill(); }\n" ++
    "    for (i = 1; i < n; i++) {\n" ++
    "      var pi = bd[i * 5 + 2]; if (pi < 0 || pi >= n) continue;\n" ++
    "      var tw = Math.max(k * 1.2, Math.min(rp(pi), rp(i)) * 1.5);\n" ++
    "      pixelLine(g, P[pi], P[i], tw, hsl(hue, 45, 26, 0.95));\n" ++
    "      pixelLine(g, P[pi], P[i], Math.max(k * 0.6, tw * 0.5), hsl(hue, 55, 44, 0.95));\n" ++
    "    }\n" ++
    "    var order = [3, 0, 2, 4, 5, 6, 1];\n" ++
    "    g.imageSmoothingEnabled = false;\n" ++
    "    for (var oi = 0; oi < order.length; oi++) {\n" ++
    "      var T = order[oi];\n" ++
    "      for (i = 0; i < n; i++) {\n" ++
    "        if (bd[i * 5] !== T) continue;\n" ++
    "        var x = P[i][0], y = P[i][1], r = Math.max(k * 0.8, rp(i)), p2 = bd[i * 5 + 2], ux = 0, uy = 0;\n" ++
    "        if (i > 0 && p2 >= 0 && p2 < n) { var lx = x - P[p2][0], ly = y - P[p2][1], ll = Math.sqrt(lx * lx + ly * ly) || 1; ux = lx / ll; uy = ly / ll; }\n" ++
    "        if (T === 3) {\n" ++
    "          g.save(); g.translate(x, y); g.rotate(Math.atan2(uy, ux));\n" ++
    "          g.fillStyle = hsl(hue + 40, 75, 66, 0.55); g.beginPath(); g.ellipse(0, 0, r * 1.9, r * 0.8, 0, 0, 6.2832); g.fill();\n" ++
    "          g.strokeStyle = hsl(hue + 40, 80, 80, 0.8); g.lineWidth = 1; g.stroke(); g.restore();\n" ++
    "        } else if (T === 1) {\n" ++
    "          var tx = x + ux * r * 2.4, ty = y + uy * r * 2.4, nx = -uy * r * 0.85, ny = ux * r * 0.85;\n" ++
    "          g.fillStyle = '#c8323a'; g.beginPath(); g.moveTo(x + nx, y + ny); g.lineTo(tx, ty); g.lineTo(x - nx, y - ny); g.closePath(); g.fill();\n" ++
    "          g.fillStyle = '#ffd8d0'; g.fillRect(tx - k * 0.4, ty - k * 0.4, k * 0.8, k * 0.8);\n" ++
    "        } else {\n" ++
    "          var Rs = Math.max(1, Math.round(r / k * 2)), sp = nodeSprite(T, hue, Rs), sz = sp.width * k / 2;\n" ++
    "          g.drawImage(sp, x - sz / 2, y - sz / 2, sz, sz);\n" ++
    "        }\n" ++
    "      }\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- the three task views ---------- */\n" ++
    "  var cvs = [], ctxs = [];\n" ++
    "  function fitCanvas(i) {\n" ++
    "    var cv = $('tc' + i); if (!cv) return null;\n" ++
    "    var w = cv.clientWidth, h = cv.clientHeight;\n" ++
    "    if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }\n" ++
    "    var g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0);\n" ++
    "    return { g: g, w: w, h: h };\n" ++
    "  }\n" ++
    "  function drawTask(t, now) {\n" ++
    "    var c = fitCanvas(t); if (!c) return;\n" ++
    "    var g = c.g, W = c.w, H = c.h, d = st[t];\n" ++
    "    var bg = g.createLinearGradient(0, 0, 0, H); bg.addColorStop(0, '#061019'); bg.addColorStop(1, '#03060a');\n" ++
    "    g.fillStyle = bg; g.fillRect(0, 0, W, H);\n" ++
    "    if (!d || !d.b.length) { g.fillStyle = '#5f5f5f'; g.font = '13px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'center'; g.fillText('waiting for a champion', W / 2, H / 2); return; }\n" ++
    "    /* the camera follows the swimmer (in the fight, the middle of the two) */\n" ++
    "    var b0 = d.b[0][1], cx = b0[3] / 1000, cy = b0[4] / 1000;\n" ++
    "    if (t === 2 && d.b.length > 1) { cx = (cx + d.b[1][1][3] / 1000) / 2; cy = (cy + d.b[1][1][4] / 1000) / 2; }\n" ++
    "    if (!cams[t]) cams[t] = [cx, cy];\n" ++
    "    cams[t][0] += (cx - cams[t][0]) * 0.08; cams[t][1] += (cy - cams[t][1]) * 0.08;\n" ++
    "    var V = 0.16, s = Math.max(W, H) / V, k = 2;\n" ++
    "    var SX = function (u) { return W / 2 + (u - cams[t][0]) * s; }, SY = function (v) { return H / 2 + (v - cams[t][1]) * s; };\n" ++
    "    /* water: a dot grid fixed to the world, so movement shows */\n" ++
    "    var step = 0.01, x0 = Math.floor((cams[t][0] - W / 2 / s) / step) * step, y0 = Math.floor((cams[t][1] - H / 2 / s) / step) * step;\n" ++
    "    g.fillStyle = 'rgba(120,170,220,0.10)';\n" ++
    "    for (var gx = x0; gx < cams[t][0] + W / 2 / s + step; gx += step) for (var gy = y0; gy < cams[t][1] + H / 2 / s + step; gy += step) {\n" ++
    "      var big = (Math.round(gx / step) % 5 === 0) && (Math.round(gy / step) % 5 === 0);\n" ++
    "      g.fillRect(Math.round(SX(gx)), Math.round(SY(gy)), big ? 2 : 1, big ? 2 : 1);\n" ++
    "    }\n" ++
    "    /* trails */\n" ++
    "    for (var bi = 0; bi < trails[t].length; bi++) {\n" ++
    "      var tr = trails[t][bi]; if (!tr || tr.length < 2) continue;\n" ++
    "      var hue = d.b[bi] ? d.b[bi][0] : 180;\n" ++
    "      for (var i = 1; i < tr.length; i++) {\n" ++
    "        g.strokeStyle = hsl(hue, 70, 60, 0.28 * i / tr.length); g.lineWidth = 2;\n" ++
    "        g.beginPath(); g.moveTo(SX(tr[i - 1][0]), SY(tr[i - 1][1])); g.lineTo(SX(tr[i][0]), SY(tr[i][1])); g.stroke();\n" ++
    "      }\n" ++
    "    }\n" ++
    "    /* the target */\n" ++
    "    if (d.tg) {\n" ++
    "      var tx = SX(d.tg[0] / 1000), ty = SY(d.tg[1] / 1000), on = tx > -20 && tx < W + 20 && ty > -20 && ty < H + 20;\n" ++
    "      if (t === 0) {\n" ++
    "        var pr = 26 + 5 * Math.sin(now / 260);\n" ++
    "        var gl = g.createRadialGradient(tx, ty, 0, tx, ty, pr * 2.2); gl.addColorStop(0, 'rgba(255,224,120,0.55)'); gl.addColorStop(0.35, 'rgba(255,190,70,0.18)'); gl.addColorStop(1, 'rgba(255,190,70,0)');\n" ++
    "        g.fillStyle = gl; g.fillRect(tx - pr * 2.2, ty - pr * 2.2, pr * 4.4, pr * 4.4);\n" ++
    "        g.fillStyle = '#fff3c4'; g.fillRect(tx - 4, ty - 4, 8, 8); g.fillStyle = '#ffd36b'; g.fillRect(tx - 6, ty - 2, 12, 4); g.fillRect(tx - 2, ty - 6, 4, 12);\n" ++
    "      } else {\n" ++
    "        var hx = 1, hy = 0;\n" ++
    "        if (preyPrev) { var mx = d.tg[0] - preyPrev[0], my = d.tg[1] - preyPrev[1], ml = Math.sqrt(mx * mx + my * my); if (ml > 0.01) { hx = mx / ml; hy = my / ml; } else if (preyPrev.length > 2) { hx = preyPrev[2]; hy = preyPrev[3]; } }\n" ++
    "        preyPrev = [d.tg[0], d.tg[1], hx, hy];\n" ++
    "        g.save(); g.translate(tx, ty); g.rotate(Math.atan2(hy, hx));\n" ++
    "        g.fillStyle = '#7dffb0'; g.fillRect(-7, -4, 12, 8); g.fillRect(5, -2, 3, 4);\n" ++
    "        g.fillStyle = '#3fbf74'; g.fillRect(-13, -5, 6, 3); g.fillRect(-13, 2, 6, 3); g.fillRect(-10, -2, 3, 4);\n" ++
    "        g.fillStyle = '#05060a'; g.fillRect(2, -2, 2, 2);\n" ++
    "        g.restore();\n" ++
    "      }\n" ++
    "      if (!on) {\n" ++
    "        var ax = clamp(tx, 18, W - 18), ay = clamp(ty, 60, H - 18), ang = Math.atan2(ty - H / 2, tx - W / 2);\n" ++
    "        g.save(); g.translate(ax, ay); g.rotate(ang); g.fillStyle = t === 0 ? '#ffd36b' : '#7dffb0';\n" ++
    "        g.beginPath(); g.moveTo(9, 0); g.lineTo(-6, -6); g.lineTo(-6, 6); g.closePath(); g.fill(); g.restore();\n" ++
    "      }\n" ++
    "    }\n" ++
    "    /* bodies */\n" ++
    "    for (bi = 0; bi < d.b.length; bi++) {\n" ++
    "      var B = d.b[bi], bd = B[1], P = [];\n" ++
    "      for (i = 0; i < bd.length / 5; i++) P.push([SX(bd[i * 5 + 3] / 1000), SY(bd[i * 5 + 4] / 1000)]);\n" ++
    "      drawMesh(g, bd, B[0], P, s, k);\n" ++
    "      if (B[3] > 0) { g.strokeStyle = 'rgba(255,70,70,' + (B[3] / 10) + ')'; g.lineWidth = 2; g.beginPath(); g.arc(P[0][0], P[0][1], 30, 0, 6.2832); g.stroke(); }\n" ++
    "      if (t === 2) {\n" ++
    "        var hp = clamp(B[2] / 100, 0, 1), bx = P[0][0] - 22, by = P[0][1] - 42;\n" ++
    "        g.fillStyle = 'rgba(0,0,0,0.6)'; g.fillRect(bx - 1, by - 1, 46, 7);\n" ++
    "        g.fillStyle = hp > 0.5 ? '#50e3c2' : hp > 0.25 ? '#f5a623' : '#ff5a5a'; g.fillRect(bx, by, 44 * hp, 5);\n" ++
    ""
}

fun part1() {
    "        g.fillStyle = 'rgba(237,237,237,0.85)'; g.font = '600 11px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'center';\n" ++
    "        g.fillText(bi === 0 ? 'champion' : 'runner-up', P[0][0], by - 5);\n" ++
    "      }\n" ++
    "    }\n" ++
    "    /* the brain's drive: thrust and turn of the first body */\n" ++
    "    var o = d.b[0];\n" ++
    "    g.fillStyle = 'rgba(143,143,143,0.9)'; g.font = '11px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'left';\n" ++
    "    g.fillText('thrust ' + (o[4] / 100).toFixed(2) + '   turn ' + (o[5] / 100).toFixed(2) + (t === 2 ? '   bite ' + (o[6] / 100).toFixed(2) : ''), 14, H - 14);\n" ++
    "    var sc = $('ts' + t); if (sc) sc.textContent = t === 2 ? (d.sc / 100).toFixed(1) : String(d.n);\n" ++
    "    var pb = $('tp' + t); if (pb) pb.style.width = Math.round(100 * d.tick / d.T) + '%';\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- champion, pools and charts ---------- */\n" ++
    "  function drawChamp() {\n" ++
    "    if (!champ) return;\n" ++
    "    var cv = $('c-cv'); if (!cv) return;\n" ++
    "    var g = cv.getContext('2d'), W = cv.width, H = cv.height, B = champ.body[0], bd = B[1], n = bd.length / 5;\n" ++
    "    g.clearRect(0, 0, W, H);\n" ++
    "    var mnx = 1e9, mny = 1e9, mxx = -1e9, mxy = -1e9, i;\n" ++
    "    for (i = 0; i < n; i++) { var x = bd[i * 5 + 3], y = bd[i * 5 + 4]; mnx = Math.min(mnx, x); mxx = Math.max(mxx, x); mny = Math.min(mny, y); mxy = Math.max(mxy, y); }\n" ++
    "    var span = Math.max(mxx - mnx, mxy - mny, 20) / 1000, s = W * 0.62 / span, P = [];\n" ++
    "    for (i = 0; i < n; i++) P.push([W / 2 + ((bd[i * 5 + 3] - (mnx + mxx) / 2) / 1000) * s, H / 2 + ((bd[i * 5 + 4] - (mny + mxy) / 2) / 1000) * s]);\n" ++
    "    drawMesh(g, bd, B[0], P, s, 2);\n" ++
    "    var cnt = [0, 0, 0, 0, 0, 0, 0]; for (i = 0; i < n; i++) cnt[bd[i * 5]]++;\n" ++
    "    $('c-title').textContent = 'Pool ' + (champ.k + 1) + ' champion';\n" ++
    "    $('c-st').textContent = 'genome #' + champ.id + ' · lineage generation ' + fmtc(champ.gen);\n" ++
    "    $('c-sub').textContent = 'running its three trials live';\n" ++
    "    var kv = [['light', (champ.sc[0] / 100).toFixed(2)], ['chase', (champ.sc[1] / 100).toFixed(2)], ['fight', (champ.sc[2] / 100).toFixed(1)],\n" ++
    "      ['neurons', champ.nn], ['synapses', champ.nc], ['body parts', n],\n" ++
    "      ['fins', cnt[3]], ['spikes', cnt[1]], ['mouths', cnt[4]]];\n" ++
    "    $('c-kv').innerHTML = kv.map(function (x) { return '<div>' + x[0] + '<b>' + x[1] + '</b></div>'; }).join('');\n" ++
    "  }\n" ++
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
    "  function frame(now) {\n" ++
    "    build();\n" ++
    "    for (var t = 0; t < 3; t++) drawTask(t, now);\n" ++
    "    requestAnimationFrame(frame);\n" ++
    "  }\n" ++
    "  requestAnimationFrame(frame);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
