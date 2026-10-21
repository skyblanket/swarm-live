module Evolve3Js

# GENERATED from src/evolve3.js by scripts/embed_js.py - edit the .js, not this file.

export [js]

fun js() {
    "/* Evolution 3 - client. Source of truth for src/Evolve3Js.sw\n" ++
    "   (python3 scripts/embed_js.py src/evolve3.js Evolve3Js src/Evolve3Js.sw).\n" ++
    "\n" ++
    "   Frame d (every tick at 1x, sampled in fast / turbo):\n" ++
    "     cr   [slot, id, species, hue, x, y, hx, hy, energy, health, size, speed, armor, attack, sight, diet,\n" ++
    "           p1, p2, p3, signal, biting, mating, gen, age, kids, kills, neurons, synapses, pain, eta*1000]  (genes *100)\n" ++
    "     acts / sens   the selected creature's neuron activations and its 18 senses (*100)\n" ++
    "     net  (sometimes) {types, e: [[src, dst, kind, w_born*100, w_now*100]]}   src >= 1000 is a sense\n" ++
    "     kar  (sometimes) its two haplotypes: a, b = [[value 0..100, dominance 0..100] x 19], brain gene counts, parents\n" ++
    "     plants meat preds obst   the world       sps [[id, count, hue]]     mean  population means\n" ++
    "     evs  [code, slot, hue, gen, x, y]: 7 birth (x: 1 sex, 2 bud, 3 immigrant), 4 starved, 5 predator, 6 eaten,\n" ++
    "          8 old age, 9 new species, 10 extinct, 11 saved, 12 resumed\n" ++
    "   The world is pixel art: everything is drawn at 1 world pixel per cell on a small canvas and scaled up. */\n" ++
    "(function () {\n" ++
    "  var $ = function (id) { return document.getElementById(id); };\n" ++
    "  var ac = $('arena-cv'), bc = $('brain-cv'), gc = $('gene-cv'), sc = $('sp-cv'), tc = $('tr-cv');\n" ++
    "  if (!ac) return;\n" ++
    "  var ag = ac.getContext('2d'), bg = bc.getContext('2d'), gg = gc.getContext('2d'), sg = sc.getContext('2d'), tg = tc.getContext('2d');\n" ++
    "  var dpr = Math.min(2, window.devicePixelRatio || 1);\n" ++
    "  var WP = 240;                                   /* world pixels per side */\n" ++
    "  var wc = document.createElement('canvas'); wc.width = WP; wc.height = WP;\n" ++
    "  var wg = wc.getContext('2d');\n" ++
    "  var bgc = null, last = null, net = null, kar = null, framesN = 0, fps = 0, fpsT = performance.now(), tpsT = 0, tpsTick = 0, tps = 0;\n" ++
    "  var histT = 0, sphist = [], trhist = [], spColor = {}, stats = {}, toastT = 0;\n" ++
    "  var sprites = {}, spriteN = 0, AW = 0, AH = 0, BW = 0, BH = 0, GW = 0, GH = 0, view = { s: 1, ox: 0, oy: 0 };\n" ++
    "  var SENS = ['bias', 'plant dir', 'plant near', 'meat dir', 'meat near', 'other dir', 'other near', 'kinship', 'its size', 'its signal',\n" ++
    "    'predator dir', 'predator near', 'threat', 'wall ahead', 'energy', 'health', 'pain', 'heard'];\n" ++
    "  var OUTS = ['turn', 'thrust', 'bite', 'signal', 'mate'];\n" ++
    "  var LOCI = ['size', 'speed', 'armor', 'attack', 'sight', 'diet', 'hue', 'pattern', 'pattern', 'pattern', 'mutation', 'plasticity', 'rule A', 'rule B', 'rule C', 'rule D', 'mod base', 'fertility', 'choosiness'];\n" ++
    "  var LGROUP = [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 3, 3, 3, 3, 3, 3, 4, 4];\n" ++
    "  var GROUPS = [{ n: 'body', c: [80, 227, 194] }, { n: 'looks', c: [255, 200, 90] }, { n: 'genetics', c: [120, 255, 140] }, { n: 'learning rule', c: [167, 139, 250] }, { n: 'mating', c: [255, 120, 190] }];\n" ++
    "  var TRAITS = [{ n: 'size', lo: 60, hi: 160, c: [255, 220, 120] }, { n: 'speed', lo: 50, hi: 180, c: [90, 200, 255] }, { n: 'armor', lo: 0, hi: 150, c: [150, 170, 200] },\n" ++
    "    { n: 'attack', lo: 0, hi: 200, c: [255, 90, 90] }, { n: 'sight', lo: 15, hi: 50, c: [80, 227, 194] }, { n: 'diet', lo: 0, hi: 100, c: [255, 140, 60] },\n" ++
    "    { n: 'mutation', lo: 30, hi: 300, c: [120, 255, 140] }, { n: 'plasticity', lo: 0, hi: 200, c: [167, 139, 250] }, { n: 'neurons', lo: 500, hi: 2400, c: [200, 200, 160] }, { n: 'synapses', lo: 500, hi: 6000, c: [255, 120, 190] }, { n: 'foraging', lo: 0, hi: 600, c: [255, 255, 255], bold: 1 }];\n" ++
    "  var TCOL = [[120, 190, 255], [245, 166, 35], [190, 120, 255]];  /* rate, modulatory, spiking */\n" ++
    "  var EVC = { 7: [80, 227, 194], 4: [245, 166, 35], 5: [255, 80, 80], 6: [255, 60, 160], 8: [140, 140, 160], 9: [255, 220, 120], 10: [120, 120, 130], 11: [80, 227, 194], 12: [80, 227, 194] };\n" ++
    "\n" ++
    "  function rgba(c, a) { return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }\n" ++
    "  function hsl(h, s, l, a) { return 'hsla(' + h + ',' + s + '%,' + l + '%,' + (a === undefined ? 1 : a) + ')'; }\n" ++
    "  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }\n" ++
    "  function fmt(n) { n = Math.round(n || 0); if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k'; return fmtc(n); }\n" ++
    "  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }\n" ++
    "  function hash(a, b) { var x = Math.imul(a ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(b + 0x632be5ab, 0xc2b2ae35); x ^= x >>> 15; x = Math.imul(x, 0x2c1b3c6d); x ^= x >>> 12; return (x >>> 0) / 4294967296; }\n" ++
    "\n" ++
    "  /* ---------- sizing ---------- */\n" ++
    "  function fit(cv, cx, w, h) { cv.width = Math.max(1, w * dpr); cv.height = Math.max(1, h * dpr); cv.style.width = w + 'px'; cv.style.height = h + 'px'; cx.setTransform(dpr, 0, 0, dpr, 0, 0); }\n" ++
    "  function resize() {\n" ++
    "    var a = $('arena'), b = $('brain'), ge = $('gene');\n" ++
    "    AW = a.clientWidth; AH = a.clientHeight; BW = b.clientWidth; BH = b.clientHeight; GW = ge.clientWidth; GH = ge.clientHeight;\n" ++
    "    fit(ac, ag, AW, AH); fit(bc, bg, BW, BH); fit(gc, gg, GW, GH);\n" ++
    "    fit(sc, sg, sc.clientWidth, sc.clientHeight); fit(tc, tg, tc.clientWidth, tc.clientHeight);\n" ++
    "    var side = Math.max(120, Math.min(AW - 20, AH - 44));\n" ++
    "    var k = Math.max(1, Math.floor(side * dpr / WP)) / dpr;  /* whole device pixels per world pixel: crisp */\n" ++
    "    view.s = WP * k; view.ox = Math.round((AW - view.s) / 2); view.oy = 36 + Math.round((AH - 36 - view.s) / 2);\n" ++
    "  }\n" ++
    "  if (window.ResizeObserver) { var ro = new ResizeObserver(resize); ro.observe($('arena')); ro.observe($('brain')); ro.observe($('gene')); } else window.addEventListener('resize', resize);\n" ++
    "\n" ++
    "  /* ---------- the slide: dithered water and rocks, drawn once ---------- */\n" ++
    "  function makeBackground(obst) {\n" ++
    "    bgc = document.createElement('canvas'); bgc.width = WP; bgc.height = WP;\n" ++
    "    var g = bgc.getContext('2d'), img = g.createImageData(WP, WP), d = img.data, x, y, i;\n" ++
    "    for (y = 0; y < WP; y++) for (x = 0; x < WP; x++) {\n" ++
    "      i = (y * WP + x) * 4;\n" ++
    "      var n = hash(x, y), v = hash(x >> 3, y >> 3), base = 7 + Math.floor(v * 4);\n" ++
    "      var spark = n > 0.995 ? 18 : 0, ch = ((x + y) & 1) && n > 0.6 ? 2 : 0;\n" ++
    "      d[i] = base + ch + spark * 0.6; d[i + 1] = base + 3 + ch + spark; d[i + 2] = base + 9 + ch + spark; d[i + 3] = 255;\n" ++
    "    }\n" ++
    "    for (var k = 0; k < (obst || []).length; k++) {\n" ++
    "      var o = obst[k], cx = o[0] / 1000 * WP, cy = o[1] / 1000 * WP, r = o[2] / 1000 * WP;\n" ++
    "      for (y = Math.floor(cy - r - 1); y <= cy + r + 1; y++) for (x = Math.floor(cx - r - 1); x <= cx + r + 1; x++) {\n" ++
    "        if (x < 0 || y < 0 || x >= WP || y >= WP) continue;\n" ++
    "        var dx = x + 0.5 - cx, dy = y + 0.5 - cy, dd = Math.sqrt(dx * dx + dy * dy);\n" ++
    "        if (dd > r) continue;\n" ++
    "        i = (y * WP + x) * 4;\n" ++
    "        var light = (-dx - dy) / (r * 1.6), edge = dd > r - 1.2, tex = hash(x * 3, y * 7) * 10;\n" ++
    "        var l = edge ? 24 : 40 + light * 22 + tex;\n" ++
    "        d[i] = l * 0.8; d[i + 1] = l * 0.85; d[i + 2] = l; d[i + 3] = 255;\n" ++
    "      }\n" ++
    "    }\n" ++
    "    g.putImageData(img, 0, 0);\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- creature sprites: built from the genes, cached ---------- */\n" ++
    "  function spriteKey(c) {\n" ++
    "    return [Math.round(c[10] / 8), Math.round(c[11] / 25), Math.round(c[12] / 25), Math.round(c[13] / 25), Math.round(c[14] / 8), Math.round(c[15] / 34),\n" ++
    "      Math.round(c[16] / 10), Math.round(c[17] / 10), Math.round(c[18] / 10), Math.round(c[3] / 12), Math.min(4, Math.floor(c[26] / 5))].join('.');\n" ++
    "  }\n" ++
    "  /* A microbe drawn from its genes, two animation frames:\n" ++
    "       body size and shape   size, speed (fast bodies are longer)\n" ++
    "       shading and pattern   hue, pattern genes (spots, bands or speckles)\n" ++
    "       shell plates          armor           spikes   attack (red if it eats meat)\n" ++
    "       eye                   sight           nucleus  brain size\n" ++
    "       cilia (slow) or a whip tail (fast, drawn live)   speed */\n" ++
    "  function buildSprite(c) {\n" ++
    "    var size = c[10] / 100, speed = c[11] / 100, armor = c[12] / 100, attack = c[13] / 100, sight = c[14] / 100, diet = c[15] / 100;\n" ++
    "    var p1 = c[16] / 100, p2 = c[17] / 100, p3 = c[18] / 100, hue = c[3], nn = c[26];\n" ++
    "    var n = 9 + 2 * Math.round((size - 0.6) * 3), W = n + 8, H = n + 6;\n" ++
    "    var cx = W / 2 - 1, cy = H / 2, rx = n / 2 * (0.9 + 0.25 * (speed - 0.5)), ry = n / 2 * (0.95 - 0.15 * (speed - 0.5));\n" ++
    "    var seed = Math.round(p1 * 10) * 131 + Math.round(p2 * 10) * 17 + Math.round(p3 * 10);\n" ++
    "    var lite = hsl(hue, 70, 64), body = hsl(hue, 58, 47), deep = hsl(hue, 62, 34), memb = hsl(hue, 70, 18);\n" ++
    "    var acc1 = hsl((hue + 30 + p2 * 200) % 360, 70, 60), acc2 = hsl((hue + 30 + p2 * 200) % 360, 60, 44);\n" ++
    "    var mode = Math.min(2, Math.floor(p3 * 3)), frames = [], f, x, y, k;\n" ++
    "    function inside(x, y) { var dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry; return dx * dx + dy * dy <= 1; }\n" ++
    "    for (f = 0; f < 2; f++) {\n" ++
    "      var cv = document.createElement('canvas'); cv.width = W; cv.height = H;\n" ++
    "      var g = cv.getContext('2d');\n" ++
    "      var px = function (x, y, col) { g.fillStyle = col; g.fillRect(x, y, 1, 1); };\n" ++
    "      /* cilia for slow bodies: little hairs that beat between the two frames */\n" ++
    "      if (speed <= 1.1) {\n" ++
    "        var nc = 10 + Math.round(size * 4);\n" ++
    "        for (k = 0; k < nc; k++) {\n" ++
    "          var a = (k + f * 0.5) / nc * 6.2832;\n" ++
    "          if (Math.cos(a) > 0.75) continue;\n" ++
    "          px(Math.round(cx + Math.cos(a) * (rx + 1.2) - 0.5), Math.round(cy + Math.sin(a) * (ry + 1.2) - 0.5), hsl(hue, 50, 70, 0.75));\n" ++
    "        }\n" ++
    "      }\n" ++
    "      for (y = 0; y < H; y++) for (x = 0; x < W; x++) {\n" ++
    "        if (!inside(x, y)) continue;\n" ++
    "        var edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);\n" ++
    "        var dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry, r2 = dx * dx + dy * dy, h1 = hash(seed + x * 7, y * 13);\n" ++
    "        var shade = -dx * 0.45 - dy * 0.75;                       /* lit from the top left */\n" ++
    "        var col = shade > 0.45 ? lite : shade < -0.35 ? deep : body;\n" ++
    "        if (mode === 0 && h1 < 0.08 + p1 * 0.25 && r2 < 0.7) col = shade < 0 ? acc2 : acc1;              /* spots */\n" ++
    "        else if (mode === 1 && Math.floor((y + p1 * 5) / 2) % 2 === 0 && r2 < 0.8) col = shade < 0 ? acc2 : acc1;  /* bands */\n" ++
    "        else if (mode === 2 && h1 > 0.9 - p1 * 0.1) col = lite;                                       /* speckles */\n" ++
    "        if (edge) col = memb;\n" ++
    "        /* armor: plates over the back, more of the body as the gene grows */\n" ++
    "        var ang = Math.atan2(dy, dx), cover = armor > 1.0 ? 1.2 : armor > 0.6 ? 0.55 : 0.1;\n" ++
    "        if (armor > 0.3 && r2 > 0.5 && -Math.sin(ang) > -cover && Math.cos(ang) < 0.85) {\n" ++
    "          var seg = Math.floor((ang + 3.1416) / (6.2832 / (6 + Math.round(armor * 4))));\n" ++
    "          col = edge ? '#4a5262' : (seg % 2 ? '#b9c4d4' : '#8c98ab');\n" ++
    "        }\n" ++
    "        px(x, y, col);\n" ++
    "      }\n" ++
    "      /* nucleus (brain size) and a few vacuoles */\n" ++
    "      var nr = 0.9 + Math.min(4, nn / 6) * 0.45, ncx = cx - rx * 0.28;\n" ++
    "      for (y = 0; y < H; y++) for (x = 0; x < W; x++) {\n" ++
    "        var ddx = x + 0.5 - ncx, ddy = y + 0.5 - cy;\n" ++
    "        if (ddx * ddx + ddy * ddy <= nr * nr && inside(x, y)) px(x, y, ddx < 0 && ddy < 0 ? hsl(hue + 180, 30, 34) : hsl(hue + 180, 35, 20));\n" ++
    "      }\n" ++
    "      for (k = 0; k < 2; k++) { var vx = Math.round(cx + (hash(seed, k) - 0.3) * rx), vy = Math.round(cy + (hash(k, seed) - 0.5) * ry); if (inside(vx, vy) && !inside(vx, vy - 2) === false) px(vx, vy, 'rgba(255,255,255,0.45)'); }\n" ++
    "      /* spikes */\n" ++
    "      var ns = Math.round(attack * 2.2), spk = diet > 0.5 ? '#ff4b3a' : '#e8ecf2', tip = diet > 0.5 ? '#ffb199' : '#ffffff', fx = Math.round(cx + rx);\n" ++
    "      for (k = 0; k < ns; k++) {\n" ++
    "        var sy = Math.round(cy + (k - (ns - 1) / 2) * 2.2), len = 1 + Math.round(attack * 1.2) - (Math.abs(k - (ns - 1) / 2) > 1 ? 1 : 0) + (f && k % 2 ? 1 : 0);\n" ++
    "        for (var j = 0; j < len; j++) px(fx + j, sy, j === len - 1 ? tip : spk);\n" ++
    "      }\n" ++
    "      /* eye */\n" ++
    "      var ex = Math.round(cx + rx * 0.42), ey = Math.round(cy - ry * 0.38);\n" ++
    "      if (sight > 0.28) { px(ex, ey - 1, '#f2f6ff'); px(ex + 1, ey - 1, '#f2f6ff'); px(ex, ey, '#f2f6ff'); px(ex + 1, ey, diet > 0.5 ? '#d01010' : '#05060a'); }\n" ++
    "      else { px(ex, ey, '#f2f6ff'); px(ex + 1, ey, diet > 0.5 ? '#d01010' : '#05060a'); }\n" ++
    "      frames.push(cv);\n" ++
    "    }\n" ++
    "    return { cv: frames, w: W, h: H, cx: Math.round(cx), cy: Math.round(cy), rx: rx, tail: Math.round(cx - rx), whip: speed > 1.1 };\n" ++
    "  }\n" ++
    "  function spriteOf(c) {\n" ++
    "    var k = spriteKey(c), s = sprites[k];\n" ++
    "    if (!s) { if (spriteN > 1500) { sprites = {}; spriteN = 0; } s = sprites[k] = buildSprite(c); spriteN++; }\n" ++
    "    return s;\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- frames ---------- */\n" ++
    "  window.SwEvents = window.SwEvents || {};\n" ++
    "  window.SwEvents.frame = function (d) {\n" ++
    "    var now = performance.now(), i;\n" ++
    "    if (d.obst) { if (!bgc) makeBackground(d.obst); }\n" ++
    "    if (last && d.tick < last.tick) { sphist = []; trhist = []; }\n" ++
    "    last = d; framesN++;\n" ++
    "    if (d.net) net = d.net;\n" ++
    "    if (d.kar) kar = d.kar;\n" ++
    "    if (now - tpsT > 1000) { if (tpsT) tps = Math.max(0, (d.tick - tpsTick) * 1000 / (now - tpsT)); tpsT = now; tpsTick = d.tick; var o = $('o-tps'); if (o) o.textContent = Math.round(tps); }\n" ++
    "    for (i = 0; i < d.evs.length; i++) addLog(d.evs[i]);\n" ++
    "    for (i = 0; i < d.sps.length; i++) spColor[d.sps[i][0]] = d.sps[i][2];\n" ++
    "    if (now - histT > 700) {\n" ++
    "      histT = now;\n" ++
    "      var m = {}; for (i = 0; i < d.sps.length; i++) m[d.sps[i][0]] = d.sps[i][1];\n" ++
    "      sphist.push(m); if (sphist.length > 160) sphist.shift();\n" ++
    "      trhist.push(d.mean.concat([d.forage])); if (trhist.length > 160) trhist.shift();\n" ++
    "    }\n" ++
    "    var nsp = d.sps.filter(function (s) { return s[1] > 0; }).length;\n" ++
    "    stat('pop', d.pop, fmtc, d.b_sex + ' sexual · ' + d.b_bud + ' budded · ' + d.b_imm + ' immigrants', d.pop < 30 ? 'warn' : 'up');\n" ++
    "    stat('gen', d.maxgen, fmtc, 'foraging ' + (d.forage / 100).toFixed(2) + ' meals / 1000 ticks', '');\n" ++
    "    stat('sp', nsp, fmtc, 'genetic clusters', nsp > 1 ? 'up' : '');\n" ++
    "    stat('procs', d.nn, fmtc, (d.pop ? (d.nn / d.pop).toFixed(1) : 0) + ' neurons per brain', '');\n" ++
    "    stat('msgs', d.nc * tps + d.nn * tps * 2, fmt, d.nc + ' synapses alive', '');\n" ++
    "    var deaths = d.d_starve + d.d_pred + d.d_eaten + d.d_old;\n" ++
    "    stat('death', deaths, fmtc, d.d_starve + ' starved · ' + d.d_eaten + ' eaten · ' + d.d_pred + ' predators · ' + d.d_old + ' old', deaths ? 'bad' : '');\n" ++
    "    var ck = $('o-ck'); if (ck) { var ago = d.tick - d.ck_tick; ck.textContent = d.ck ? ('checkpoint · ' + (tps > 0 ? Math.round(ago / tps) + 's ago' : ago + ' ticks ago')) : 'checkpoint · not yet'; }\n" ++
    "    tog('b-pred', 'Predators: ', d.pred_on); tog('b-plast', 'Learning: ', d.plast);\n" ++
    "    var sb = document.querySelectorAll('[data-speed]'); for (i = 0; i < sb.length; i++) sb[i].classList.toggle('on', Number(sb[i].getAttribute('data-speed')) === Math.max(1, d.speed));\n" ++
    "    var sr = rowOf(d.sel);\n" ++
    "    var ah = $('ah'); if (ah) ah.innerHTML = '<b>' + d.pop + '</b> creatures &middot; <b>' + nsp + '</b> species &middot; click one to open its brain and genes';\n" ++
    "    var bh = $('bh'); if (bh) bh.innerHTML = sr ? '<b>#' + sr[1] + '</b> &middot; gen ' + sr[22] + ' &middot; ' + sr[26] + ' neurons, ' + sr[27] + ' synapses &middot; ' + sr[24] + ' kids, ' + sr[25] + ' kills &middot; age ' + Math.round(sr[23] / 33) + 's' : 'no creature';\n" ++
    "    var gh = $('gh'); if (gh) gh.innerHTML = kar ? '<b>genome</b> &middot; two copies of every gene &middot; ' + (kar.mom ? (kar.mom === kar.dad ? 'budded from #' + kar.mom : 'child of #' + kar.mom + ' &times; #' + kar.dad) : 'founder or immigrant') : 'genome';\n" ++
    "    legendSpecies(d);\n" ++
    "  };\n" ++
    "  function rowOf(slot) { if (!last) return null; for (var i = 0; i < last.cr.length; i++) if (last.cr[i][0] === slot) return last.cr[i]; return null; }\n" ++
    "  function tog(id, label, on) { var b = $(id); if (b) { b.textContent = label + (on ? 'on' : 'off'); b.classList.toggle('on', !!on); } }\n" ++
    "\n" ++
    "  function toast(t) { var el = $('toast'); if (!el) return; el.textContent = t; el.classList.add('show'); clearTimeout(toastT); toastT = setTimeout(function () { el.classList.remove('show'); }, 2600); }\n" ++
    "  function addLog(e) {\n" ++
    "    var el = $('log'); if (!el) return;\n" ++
    "    var code = e[0], txt = '';\n" ++
    "    if (code === 7) txt = (e[4] === 1 ? 'Born of two parents' : e[4] === 2 ? 'Budded (self-fertilised)' : 'Immigrant arrived') + ' &middot; gen ' + e[3] + ', ' + e[5] + ' neurons';\n" ++
    "    else if (code === 4) txt = 'Starved at ' + Math.round(e[4] / 33) + 's (gen ' + e[3] + ', ' + e[5] + ' kids)';\n" ++
    "    else if (code === 5) txt = 'Caught by a predator (gen ' + e[3] + ')';\n" ++
    "    else if (code === 6) txt = 'Eaten by another creature (gen ' + e[3] + ')';\n" ++
    "    else if (code === 8) txt = 'Died of old age, ' + e[5] + ' kids (gen ' + e[3] + ')';\n" ++
    "    else if (code === 9) txt = 'New species #' + e[3] + ' split off';\n" ++
    "    else if (code === 10) txt = 'Species #' + e[3] + ' went extinct';\n" ++
    "    else if (code === 11) { txt = 'Checkpoint saved: ' + e[4] + ' genomes, gen ' + e[3]; toast('Checkpoint saved · ' + e[4] + ' genomes'); }\n" ++
    "    else if (code === 12) { txt = 'Resumed from checkpoint: ' + e[4] + ' genomes, gen ' + e[3]; toast('Resumed from checkpoint'); }\n" ++
    "    if ((code === 7 && e[4] !== 1) || code === 8) { if (Math.random() < 0.7) return; }\n" ++
    "    var col = code === 9 || code === 10 || code === 7 ? hsl(e[2], 70, 55) : rgba(EVC[code] || [200, 200, 200], 1);\n" ++
    "    var row = document.createElement('div'); row.className = 'ev';\n" ++
    "    row.innerHTML = '<i style=\"background:' + col + ';box-shadow:0 0 0 2px ' + rgba(EVC[code] || [255, 255, 255], 0.35) + '\"></i><span>' + txt + '</span>';\n" ++
    "    el.insertBefore(row, el.firstChild); while (el.children.length > 10) el.removeChild(el.lastChild);\n" ++
    "  }\n" ++
    "  function legendSpecies(d) {\n" ++
    "    var el = $('sp-leg'); if (!el) return;\n" ++
    "    var top = d.sps.filter(function (s) { return s[1] > 0; }).sort(function (a, b) { return b[1] - a[1]; }).slice(0, 6), h = '';\n" ++
    "    for (var i = 0; i < top.length; i++) h += '<span><i style=\"background:' + hsl(top[i][2], 70, 55) + '\"></i>#' + top[i][0] + ' &middot; ' + top[i][1] + '</span>';\n" ++
    "    el.innerHTML = h;\n" ++
    "    var hs = $('h-sp'); if (hs) hs.textContent = top.length ? 'largest: #' + top[0][0] : '';\n" ++
    "    var tl = $('tr-leg');\n" ++
    "    if (tl && d.mean) tl.innerHTML = TRAITS.map(function (t, k) { var v = k === 10 ? d.forage : d.mean[k]; if (k === 10) return '<span style=\"color:#fff;font-weight:600\">foraging ' + (v / 100).toFixed(2) + '</span>'; return '<span style=\"color:' + rgba(t.c, 1) + '\">' + t.n + ' ' + (k >= 8 ? (v / 100).toFixed(1) : k === 7 ? (v / 1000).toFixed(3) : (v / 100).toFixed(2)) + '</span>'; }).join('');\n" ++
    "  }\n" ++
    "\n" ++
    "  function stat(id, v, f, sub, tone) {\n" ++
    "    var s = stats[id] || (stats[id] = { cur: v, tgt: v, shown: '' }); s.tgt = v; s.fmt = f;\n" ++
    "    var d = $('d-' + id); if (d && d.textContent !== sub) { d.textContent = sub; d.className = 'chip ' + (tone || ''); }\n" ++
    "  }\n" ++
    "  function tickStats() {\n" ++
    "    for (var id in stats) {\n" ++
    "      var s = stats[id]; s.cur += (s.tgt - s.cur) * 0.2; if (Math.abs(s.tgt - s.cur) < 0.4) s.cur = s.tgt;\n" ++
    "      var t = s.fmt(s.cur), el = $('v-' + id); if (el && t !== s.shown) { el.textContent = t; s.shown = t; }\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- controls ---------- */\n" ++
    "  document.addEventListener('click', function (e) {\n" ++
    "    var t = e.target.closest ? e.target.closest('[data-speed],#b-pred,#b-plast,#b-save,#b-load,#b-reset') : null;\n" ++
    "    if (!t) return;\n" ++
    "    if (t.hasAttribute('data-speed')) window.swSend('speed', { k: Number(t.getAttribute('data-speed')) });\n" ++
    "    else if (t.id === 'b-pred') window.swSend('pred', {});\n" ++
    "    else if (t.id === 'b-plast') window.swSend('plast', {});\n" ++
    "    else if (t.id === 'b-save') { window.swSend('save', {}); toast('Saving checkpoint...'); }\n" ++
    "    else if (t.id === 'b-load') { window.swSend('load', {}); toast('Loading checkpoint...'); }\n" ++
    "    else if (t.id === 'b-reset') { if (confirm('Start a new random world? (The last checkpoint stays on disk.)')) { sphist = []; trhist = []; window.swSend('reset', {}); } }\n" ++
    "  });\n" ++
    "  ac.addEventListener('mousedown', function (e) {\n" ++
    "    if (!last) return;\n" ++
    "    var r = ac.getBoundingClientRect(), mx = (e.clientX - r.left - view.ox) / view.s, my = (e.clientY - r.top - view.oy) / view.s, best = -1, bd = 0.05 * 0.05;\n" ++
    "    for (var i = 0; i < last.cr.length; i++) { var c = last.cr[i], dx = c[4] / 1000 - mx, dy = c[5] / 1000 - my, d2 = dx * dx + dy * dy; if (d2 < bd) { bd = d2; best = c[0]; } }\n" ++
    "    if (best >= 0) { window.swSend('sel', { slot: best }); net = null; kar = null; }\n" ++
    "  });\n" ++
    "\n" ++
    "  /* ---------- draw: the world (pixel art) ---------- */\n" ++
    "  function W(u) { return Math.round(u / 1000 * WP); }\n" ++
    "  function drawWorld(now) {\n" ++
    "    var g = wg, d = last, i, k, f = Math.floor(now / 220) & 1;\n" ++
    "    if (bgc) g.drawImage(bgc, 0, 0); else { g.fillStyle = '#080a10'; g.fillRect(0, 0, WP, WP); }\n" ++
    "    if (!d) return;\n" ++
    "    /* plants: algae sprouts */\n" ++
    "    for (i = 0; i < d.plants.length; i++) {\n" ++
    "      var x = W(d.plants[i][0]), y = W(d.plants[i][1]), h = hash(d.plants[i][0], d.plants[i][1]);\n" ++
    "      g.fillStyle = '#1f7a5c'; g.fillRect(x - 1, y, 3, 1); g.fillRect(x, y - 1, 1, 3);\n" ++
    "      g.fillStyle = (f ^ (h > 0.5)) ? '#50e3c2' : '#3cc7a5'; g.fillRect(x, y, 1, 1);\n" ++
    "      if (h > 0.6) { g.fillStyle = '#2aa383'; g.fillRect(x + 1, y - 2, 1, 1); }\n" ++
    "    }\n" ++
    "    /* meat: what is left of the dead */\n" ++
    "    for (i = 0; i < d.meat.length; i++) {\n" ++
    "      var mx = W(d.meat[i][0]), my = W(d.meat[i][1]), r = d.meat[i][2] > 30 ? 2 : 1;\n" ++
    "      g.fillStyle = '#6b1d24'; g.fillRect(mx - r, my - r + 1, r * 2 + 1, r * 2);\n" ++
    "      g.fillStyle = '#c4423f'; g.fillRect(mx - r + 1, my - r, r * 2 - 1, r * 2 - 1 || 1);\n" ++
    "      g.fillStyle = '#ffb3a1'; g.fillRect(mx - r + 1, my - r, 1, 1);\n" ++
    "    }\n" ++
    "    /* predators */\n" ++
    "    for (i = 0; i < d.preds.length; i++) drawPred(g, d.preds[i], now, f);\n" ++
    "    /* creatures */\n" ++
    "    var sel = null;\n" ++
    "    for (i = 0; i < d.cr.length; i++) { var c = d.cr[i]; if (c[0] === d.sel) sel = c; drawCreature(g, c, now); }\n" ++
    "    if (sel) {\n" ++
    "      var sx = W(sel[4]), sy = W(sel[5]), rr = Math.round(sel[14] / 100 * WP);\n" ++
    "      g.fillStyle = 'rgba(255,255,255,0.22)';\n" ++
    "      for (k = 0; k < 64; k++) { var a = k / 64 * 6.2832 + now / 4000; g.fillRect(Math.round(sx + Math.cos(a) * rr), Math.round(sy + Math.sin(a) * rr), 1, 1); }\n" ++
    "      var q = 9 + (f ? 1 : 0); g.fillStyle = '#fff';\n" ++
    "      g.fillRect(sx - q, sy - q, 3, 1); g.fillRect(sx - q, sy - q, 1, 3); g.fillRect(sx + q - 2, sy - q, 3, 1); g.fillRect(sx + q, sy - q, 1, 3);\n" ++
    "      g.fillRect(sx - q, sy + q, 3, 1); g.fillRect(sx - q, sy + q - 2, 1, 3); g.fillRect(sx + q - 2, sy + q, 3, 1); g.fillRect(sx + q, sy + q - 2, 1, 3);\n" ++
    "    }\n" ++
    "  }\n" ++
    "  function drawPred(g, pr, now, f) {\n" ++
    "    var x = W(pr[0]), y = W(pr[1]), mode = pr[2], t = pr[3], k;\n" ++
    "    var body = mode === 1 ? '#ff3b3b' : mode === 3 ? '#ffb02e' : mode === 2 ? '#6b4a52' : '#d9534f';\n" ++
    "    if (mode === 3) {   /* stalking: a ring of warning that tightens */\n" ++
    "      var rr = Math.round(10 + 24 * clamp(t / 55, 0, 1));\n" ++
    "      g.fillStyle = (Math.floor(now / 120) & 1) ? '#ffb02e' : '#a86a10';\n" ++
    "      for (k = 0; k < 48; k++) { if (k % 3 === 2) continue; var a = k / 48 * 6.2832; g.fillRect(Math.round(x + Math.cos(a) * rr), Math.round(y + Math.sin(a) * rr), 1, 1); }\n" ++
    "      g.fillStyle = '#ffd36b'; g.fillRect(x, y - 11, 1, 4); g.fillRect(x, y - 6, 1, 1);\n" ++
    "    }\n" ++
    "    var wob = f ? 1 : 0;\n" ++
    "    g.fillStyle = body;\n" ++
    "    g.fillRect(x - 4, y - 3 - wob, 9, 7 + wob * 2); g.fillRect(x - 3, y - 5, 7, 11); g.fillRect(x - 5, y - 1, 11, 3);\n" ++
    "    for (k = 0; k < 8; k++) { var aa = k / 8 * 6.2832 + now / (mode === 1 ? 200 : 900); g.fillRect(Math.round(x + Math.cos(aa) * 6), Math.round(y + Math.sin(aa) * 6), 1, 1); }\n" ++
    "    g.fillStyle = mode === 2 ? '#2a1d22' : '#fff'; g.fillRect(x - 2, y - 2, 2, 2); g.fillRect(x + 1, y - 2, 2, 2);\n" ++
    "    if (mode !== 2) { g.fillStyle = '#000'; g.fillRect(x - 1, y - 1, 1, 1); g.fillRect(x + 2, y - 1, 1, 1); g.fillStyle = '#fff'; g.fillRect(x - 2, y + 2, 1, 1); g.fillRect(x, y + 2, 1, 1); g.fillRect(x + 2, y + 2, 1, 1); }\n" ++
    "    else { g.fillStyle = 'rgba(200,200,230,0.7)'; var zz = Math.floor(now / 500) % 3; g.fillRect(x + 5 + zz, y - 8 - zz * 2, 2, 1); }\n" ++
    "  }\n" ++
    "  function drawCreature(g, c, now) {\n" ++
    "    var s = spriteOf(c), x = W(c[4]), y = W(c[5]), flip = c[6] < 0, wig = Math.floor(now / 90 + c[1]) % 3, k;\n" ++
    "    var sig = c[19] / 100;\n" ++
    "    if (Math.abs(sig) > 0.5) {   /* bioluminescent signal: cyan for +, magenta for - */\n" ++
    "      g.fillStyle = sig > 0 ? 'rgba(80,227,255,0.35)' : 'rgba(255,80,220,0.35)';\n" ++
    "      var gr = Math.round(s.h / 2 + 2);\n" ++
    "      for (k = 0; k < 16; k++) { var a = k / 16 * 6.2832; g.fillRect(Math.round(x + Math.cos(a) * gr), Math.round(y + Math.sin(a) * gr), 1, 1); }\n" ++
    "    }\n" ++
    "    g.save(); g.translate(x, y); if (flip) g.scale(-1, 1);\n" ++
    "    /* tail: flagella length from speed */\n" ++
    "    if (s.whip) {\n" ++
    "      var tl = 3 + Math.round((c[11] / 100) * 3), tx = s.tail - s.cx - 1;\n" ++
    "      g.fillStyle = hsl(c[3], 55, 72, 0.9);\n" ++
    "      for (k = 0; k < tl; k++) g.fillRect(tx - k, Math.round(Math.sin(k * 1.3 + wig * 2.1)), 1, 1);\n" ++
    "    }\n" ++
    "    g.drawImage(s.cv[Math.floor(now / 160 + c[1]) & 1], -s.cx, -s.cy);\n" ++
    "    if (c[20]) { g.fillStyle = '#fff'; g.fillRect(Math.round(s.rx) + 1, -1, 2, 1); g.fillRect(Math.round(s.rx) + 1, 1, 2, 1); }\n" ++
    "    g.restore();\n" ++
    "    if (c[28] > 0) { g.fillStyle = 'rgba(255,60,60,0.8)'; g.fillRect(x - 1, y - Math.round(s.h / 2) - 2, 3, 1); }\n" ++
    "    if (c[21] && c[8] > 50) { g.fillStyle = '#ff78be'; g.fillRect(x + 3, y - Math.round(s.h / 2) - 2, 1, 1); g.fillRect(x + 5, y - Math.round(s.h / 2) - 2, 1, 1); g.fillRect(x + 3, y - Math.round(s.h / 2) - 1, 3, 1); g.fillRect(x + 4, y - Math.round(s.h / 2), 1, 1); }\n" ++
    "    /* energy pip bar */\n" ++
    "    var e = clamp(Math.round(c[8] / 20), 0, 5); g.fillStyle = c[8] > 35 ? '#50e3c2' : '#f5a623';\n" ++
    "    for (k = 0; k < e; k++) g.fillRect(x - 2 + k, y + Math.round(s.h / 2) + 1, 1, 1);\n" ++
    "  }\n" ++
    "  function drawArena(now) {\n" ++
    "    ag.clearRect(0, 0, AW, AH);\n" ++
    "    drawWorld(now);\n" ++
    "    ag.imageSmoothingEnabled = false;\n" ++
    "    ag.drawImage(wc, view.ox, view.oy, view.s, view.s);\n" ++
    "    ag.strokeStyle = 'rgba(255,255,255,0.12)'; ag.lineWidth = 1; ag.strokeRect(view.ox - 0.5, view.oy - 0.5, view.s + 1, view.s + 1);\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- draw: the brain ---------- */\n" ++
    "  function nodePos(kind, i, n) {\n" ++
    "    if (kind === 's') return [74, 30 + (BH - 44) * (i + 0.5) / 18];\n" ++
    "    if (kind === 'o') return [BW - 66, BH * (0.2 + i * 0.15)];\n" ++
    "    var hx = 0.5 + (hash(i, 7) - 0.5) * 0.36, hy = 0.12 + 0.76 * ((i - 5 + 0.5) / Math.max(1, n - 5));\n" ++
    "    return [74 + (BW - 140 - 74) * hx + 20, 30 + (BH - 44) * hy];\n" ++
    "  }\n" ++
    "  function drawBrain(now) {\n" ++
    "    bg.clearRect(0, 0, BW, BH);\n" ++
    "    var sr = last ? rowOf(last.sel) : null;\n" ++
    "    if (!sr || !last.acts.length) return;\n" ++
    "    var acts = last.acts, sens = last.sens, n = acts.length, i, k, types = net && net.types ? net.types : [];\n" ++
    "    var P = []; for (i = 0; i < n; i++) P.push(i < 5 ? nodePos('o', i, n) : nodePos('h', i, n));\n" ++
    "    bg.font = '10px ui-sans-serif,-apple-system,sans-serif';\n" ++
    "    /* synapses */\n" ++
    "    if (net && net.e) {\n" ++
    "      for (k = 0; k < net.e.length; k++) {\n" ++
    "        var e = net.e[k], src = e[0], dst = e[1]; if (dst >= n) continue;\n" ++
    "        var a = src >= 1000 ? nodePos('s', src - 1000, n) : P[src], b = P[dst]; if (!a || !b) continue;\n" ++
    "        var w = e[4] / 100, w0 = e[3] / 100, learned = Math.abs(w - w0) > 0.15, mod = e[2] === 1;\n" ++
    "        var pre = src >= 1000 ? (sens[src - 1000] || 0) / 100 : (acts[src] || 0) / 100;\n" ++
    "        var col = mod ? [245, 166, 35] : w >= 0 ? [90, 170, 255] : [255, 90, 90];\n" ++
    "        bg.strokeStyle = rgba(col, 0.12 + Math.min(0.5, Math.abs(w) * 0.12) + Math.min(0.35, Math.abs(pre) * Math.abs(w) * 0.15));\n" ++
    "        bg.lineWidth = 0.6 + Math.min(2.4, Math.abs(w) * 0.6);\n" ++
    "        if (mod) bg.setLineDash([3, 3]);\n" ++
    "        var mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2 - 18 * (src === dst ? 2 : 1);\n" ++
    "        bg.beginPath(); bg.moveTo(a[0], a[1]); bg.quadraticCurveTo(mx, my, b[0], b[1]); bg.stroke(); bg.setLineDash([]);\n" ++
    "        if (learned) { bg.strokeStyle = 'rgba(167,139,250,0.55)'; bg.lineWidth = 0.8; bg.beginPath(); bg.moveTo(a[0], a[1]); bg.quadraticCurveTo(mx, my + 3, b[0], b[1]); bg.stroke(); }\n" ++
    "        if (Math.abs(pre) > 0.25) {   /* a message in flight */\n" ++
    "          var t = ((now / 700) + k * 0.37) % 1, qx = (1 - t) * (1 - t) * a[0] + 2 * (1 - t) * t * mx + t * t * b[0], qy = (1 - t) * (1 - t) * a[1] + 2 * (1 - t) * t * my + t * t * b[1];\n" ++
    "          bg.fillStyle = rgba(col, 0.9); bg.fillRect(qx - 1, qy - 1, 2, 2);\n" ++
    "        }\n" ++
    "      }\n" ++
    "    }\n" ++
    "    /* senses */\n" ++
    "    bg.textAlign = 'right';\n" ++
    "    for (i = 0; i < 18; i++) {\n" ++
    "      var sp = nodePos('s', i, n), v = (sens[i] || 0) / 100, av = Math.min(1, Math.abs(v));\n" ++
    "      bg.fillStyle = rgba(v >= 0 ? [80, 227, 194] : [255, 120, 120], 0.15 + av * 0.85); bg.fillRect(sp[0] - 3, sp[1] - 3, 6, 6);\n" ++
    "      bg.fillStyle = av > 0.05 ? '#cfcfcf' : '#5a5a5a'; bg.fillText(SENS[i], sp[0] - 8, sp[1] + 3.5);\n" ++
    "    }\n" ++
    "    /* neurons */\n" ++
    "    for (i = 0; i < n; i++) {\n" ++
    "      var q = P[i], ty = types[i] || 0, v2 = (acts[i] || 0) / 100, av2 = Math.min(1, Math.abs(v2)), c = TCOL[ty] || TCOL[0], r = i < 5 ? 8 : 5;\n" ++
    "      var gl = bg.createRadialGradient(q[0], q[1], 0, q[0], q[1], r * 3.2); gl.addColorStop(0, rgba(c, 0.1 + av2 * 0.5)); gl.addColorStop(1, rgba(c, 0));\n" ++
    "      bg.fillStyle = gl; bg.fillRect(q[0] - r * 3.2, q[1] - r * 3.2, r * 6.4, r * 6.4);\n" ++
    "      bg.fillStyle = rgba(c, 0.3 + av2 * 0.7);\n" ++
    "      if (ty === 2) { bg.beginPath(); bg.moveTo(q[0], q[1] - r); bg.lineTo(q[0] + r, q[1]); bg.lineTo(q[0], q[1] + r); bg.lineTo(q[0] - r, q[1]); bg.closePath(); bg.fill(); }\n" ++
    "      else if (ty === 1) bg.fillRect(q[0] - r * 0.85, q[1] - r * 0.85, r * 1.7, r * 1.7);\n" ++
    "      else { bg.beginPath(); bg.arc(q[0], q[1], r, 0, 6.2832); bg.fill(); }\n" ++
    "      bg.strokeStyle = v2 < 0 ? 'rgba(255,90,90,0.8)' : 'rgba(255,255,255,0.35)'; bg.lineWidth = 1; bg.beginPath(); bg.arc(q[0], q[1], r + 1.5, 0, 6.2832); bg.stroke();\n" ++
    "      if (i < 5) { bg.textAlign = 'left'; bg.fillStyle = '#ededed'; bg.font = '500 11px ui-sans-serif,-apple-system,sans-serif'; bg.fillText(OUTS[i], q[0] + 14, q[1] + 4); bg.font = '10px ui-sans-serif,-apple-system,sans-serif'; bg.fillStyle = '#777'; bg.fillText((v2 >= 0 ? '+' : '') + v2.toFixed(2), q[0] + 14, q[1] + 16); }\n" ++
    "    }\n" ++
    "    /* legend */\n" ++
    "    bg.textAlign = 'left'; bg.font = '10px ui-sans-serif,-apple-system,sans-serif';\n" ++
    "    var lx = 12, ly = BH - 10, items = [['rate', TCOL[0]], ['modulatory', TCOL[1]], ['spiking', TCOL[2]], ['learned', [167, 139, 250]]];\n" ++
    "    for (k = 0; k < items.length; k++) { bg.fillStyle = rgba(items[k][1], 0.9); bg.fillRect(lx, ly - 7, 7, 7); bg.fillStyle = '#8f8f8f'; bg.fillText(items[k][0], lx + 11, ly); lx += bg.measureText(items[k][0]).width + 26; }\n" ++
    "  }\n" ++
    "\n" ++
    "  /* ---------- draw: the genome (two chromosomes) ---------- */\n" ++
    "  function drawGenome(now) {\n" ++
    "    gg.clearRect(0, 0, GW, GH);\n" ++
    "    if (!kar) return;\n" ++
    "    var L = 26, R = GW - 14, top = 40, bw = (R - L) / 19, ch = Math.min(40, (GH - 110) / 2.6), i;\n" ++
    "    var rows = [['A', kar.a, kar.an], ['B', kar.b, kar.bn]];\n" ++
    "    for (var r = 0; r < 2; r++) {\n" ++
    "      var y0 = top + r * (ch + 22), al = rows[r][1];\n" ++
    "      gg.fillStyle = '#8f8f8f'; gg.font = '600 11px ui-sans-serif,-apple-system,sans-serif'; gg.textAlign = 'left'; gg.fillText(rows[r][0], 10, y0 + ch / 2 + 4);\n" ++
    "      /* chromosome body: rounded bar */\n" ++
    "      gg.fillStyle = '#121418'; roundRect(gg, L, y0, R - L, ch, ch / 2.4); gg.fill();\n" ++
    "      for (i = 0; i < 19 && i < al.length; i++) {\n" ++
    "        var v = al[i][0] / 100, dom = al[i][1] / 100, c = GROUPS[LGROUP[i]].c, x = L + i * bw;\n" ++
    "        var other = rows[1 - r][1][i], het = other && Math.abs(other[0] - al[i][0]) > 12;\n" ++
    "        gg.fillStyle = rgba(c, 0.18 + 0.75 * v); gg.fillRect(x + 1.5, y0 + 3, bw - 3, ch - 6);\n" ++
    "        /* dominance: a bright cap whose height is the dominance */\n" ++
    "        gg.fillStyle = 'rgba(255,255,255,' + (0.2 + dom * 0.6) + ')'; gg.fillRect(x + 1.5, y0 + 3, bw - 3, Math.max(1.5, (ch - 6) * 0.22 * dom));\n" ++
    "        if (het) { gg.fillStyle = 'rgba(255,255,255,' + (0.5 + 0.4 * Math.sin(now / 300 + i)) + ')'; gg.fillRect(x + bw / 2 - 1, y0 + ch + 2, 2, 3); }\n" ++
    "      }\n" ++
    "      gg.fillStyle = '#6b6b6b'; gg.font = '10px ui-sans-serif,-apple-system,sans-serif'; gg.textAlign = 'right';\n" ++
    "      gg.fillText('brain genes: ' + rows[r][2][0] + ' neurons, ' + rows[r][2][1] + ' synapses', R, y0 - 5);\n" ++
    "    }\n" ++
    "    /* locus labels and the expressed trait */\n" ++
    "    var sr = last ? rowOf(last.sel) : null, ly = top + 2 * (ch + 22) + 6;\n" ++
    "    gg.save(); gg.font = '9.5px ui-sans-serif,-apple-system,sans-serif'; gg.textAlign = 'right';\n" ++
    "    for (i = 0; i < 19; i++) { gg.save(); gg.translate(L + i * bw + bw / 2 + 3, ly); gg.rotate(-1.0); gg.fillStyle = rgba(GROUPS[LGROUP[i]].c, 0.85); gg.fillText(LOCI[i], 0, 0); gg.restore(); }\n" ++
    "    gg.restore();\n" ++
    "    var gx = 10, gy = GH - 10; gg.font = '10px ui-sans-serif,-apple-system,sans-serif'; gg.textAlign = 'left';\n" ++
    "    for (i = 0; i < GROUPS.length; i++) { gg.fillStyle = rgba(GROUPS[i].c, 0.9); gg.fillRect(gx, gy - 7, 7, 7); gg.fillStyle = '#8f8f8f'; gg.fillText(GROUPS[i].n, gx + 11, gy); gx += gg.measureText(GROUPS[i].n).width + 24; }\n" ++
    "    gg.fillStyle = '#6b6b6b'; gg.textAlign = 'right'; gg.fillText('bright cap = dominance  ·  tick = the two copies differ', GW - 12, gy);\n" ++
    "  }\n" ++
    "  function roundRect(g, x, y, w, h, r) { g.beginPath(); g.moveTo(x + r, y); g.lineTo(x + w - r, y); g.quadraticCurveTo(x + w, y, x + w, y + r); g.lineTo(x + w, y + h - r); g.quadraticCurveTo(x + w, y + h, x + w - r, y + h); g.lineTo(x + r, y + h); g.quadraticCurveTo(x, y + h, x, y + h - r); g.lineTo(x, y + r); g.quadraticCurveTo(x, y, x + r, y); g.closePath(); }\n" ++
    "\n" ++
    "  /* ---------- charts ---------- */\n" ++
    "  function drawSpecies() {\n" ++
    "    var w = sc.clientWidth, h = sc.clientHeight; sg.clearRect(0, 0, w, h);\n" ++
    "    if (sphist.length < 2) return;\n" ++
    "    var ids = {}, i, k; for (i = 0; i < sphist.length; i++) for (k in sphist[i]) ids[k] = 1;\n" ++
    "    var order = Object.keys(ids).sort(function (a, b) { return Number(a) - Number(b); });\n" ++
    "    var maxT = 0; for (i = 0; i < sphist.length; i++) { var t = 0; for (k in sphist[i]) t += sphist[i][k]; if (t > maxT) maxT = t; }\n" ++
    "    maxT = Math.max(maxT, 10);\n" ++
    "    var base = []; for (i = 0; i < sphist.length; i++) base.push(0);\n" ++
    "    function X(i) { return i / 159 * w; }\n" ++
    "    for (var o = 0; o < order.length; o++) {\n" ++
    "      var id = order[o], top = [], any = false;\n" ++
    "      for (i = 0; i < sphist.length; i++) { var v = sphist[i][id] || 0; if (v) any = true; top.push(base[i] + v); }\n" ++
    "      if (!any) continue;\n" ++
    "      sg.beginPath(); sg.moveTo(X(0), h - base[0] / maxT * h);\n" ++
    "      for (i = 0; i < sphist.length; i++) sg.lineTo(X(i), h - top[i] / maxT * h);\n" ++
    "      for (i = sphist.length - 1; i >= 0; i--) sg.lineTo(X(i), h - base[i] / maxT * h);\n" ++
    "      sg.closePath(); sg.fillStyle = hsl(spColor[id] || 0, 65, 52, 0.85); sg.fill();\n" ++
    "      base = top;\n" ++
    "    }\n" ++
    "  }\n" ++
    "  function drawTraits() {\n" ++
    "    var w = tc.clientWidth, h = tc.clientHeight; tg.clearRect(0, 0, w, h);\n" ++
    "    tg.strokeStyle = 'rgba(255,255,255,0.06)'; tg.lineWidth = 1;\n" ++
    "    for (var q = 0; q <= 4; q++) { var y = 4 + q * (h - 8) / 4; tg.beginPath(); tg.moveTo(0, y); tg.lineTo(w, y); tg.stroke(); }\n" ++
    "    if (trhist.length < 2) return;\n" ++
    "    for (var s = 0; s < TRAITS.length; s++) {\n" ++
    "      var T = TRAITS[s];\n" ++
    "      tg.beginPath();\n" ++
    "      for (var i = 0; i < trhist.length; i++) { var v = (trhist[i][s] - T.lo) / (T.hi - T.lo), X1 = i / 159 * w, Y1 = h - 4 - clamp(v, 0, 1) * (h - 8); if (i === 0) tg.moveTo(X1, Y1); else tg.lineTo(X1, Y1); }\n" ++
    "      tg.strokeStyle = rgba(T.c, T.bold ? 1 : 0.75); tg.lineWidth = T.bold ? 2.4 : 1.2; tg.stroke();\n" ++
    "    }\n" ++
    "  }\n" ++
    "\n" ++
    "  function frame(now) {\n" ++
    "    requestAnimationFrame(frame);\n" ++
    "    if (now - fpsT > 1000) { fps = framesN; framesN = 0; fpsT = now; var f = $('o-fps'); if (f) f.textContent = fps; }\n" ++
    "    tickStats();\n" ++
    "    if (!AW) { resize(); return; }\n" ++
    "    drawArena(now); drawBrain(now); drawGenome(now); drawSpecies(); drawTraits();\n" ++
    "  }\n" ++
    "  window.__swEvolve3 = { get last() { return last; }, sprite: spriteOf };\n" ++
    "  resize();\n" ++
    "  requestAnimationFrame(frame);\n" ++
    "})();\n" ++
    "\n" ++
    ""
}
