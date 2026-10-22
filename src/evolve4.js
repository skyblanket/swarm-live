/* Evolution 4 - client. Source of truth for src/Evolve4Js.sw
   (python3 scripts/embed_js.py src/evolve4.js Evolve4Js src/Evolve4Js.sw).

   Evolution 4 creatures have evolved physical bodies: row[30] is the body, five numbers per node
   [type, radius*10000, parent index, x, y] (type 6 core, 0 body, 1 spike, 2 armor, 3 fin, 4 mouth, 5 eye);
   row[31] mass, [32] node count, [33] sight*100, [34] spike power, [35] [spikes, armor, fins, mouths, muscles].

   Frame d (every tick at 1x, sampled in fast / turbo):
     cr   [slot, id, species, hue, x, y, hx, hy, energy, health, size, speed, armor, attack, sight, diet,
           p1, p2, p3, signal, biting, mating, gen, age, kids, kills, neurons, synapses, pain, eta*1000]  (genes *100)
     acts / sens   the selected creature's neuron activations and its 18 senses (*100)
     net  (sometimes) {types, e: [[src, dst, kind, w_born*100, w_now*100]]}   src >= 1000 is a sense
     kar  (sometimes) its two haplotypes [[value 0..100, dominance 0..100] x 19], brain gene counts, parents
     hist (sometimes) the run's history, newest first:
          [tick, gen, pop, foraging*100, neurons/brain*100, attack*100, plasticity*1000, size*100, armor*100, species, diet*100]
     plants meat preds obst   the world       sps [[id, count, hue]]
     evs  [code, slot, hue, gen, x, y]: 7 birth, 4 starved, 5 predator, 6 eaten, 8 old age, 9 new species, 10 extinct, 11 saved, 12 resumed

   Drawing: the slide (water, rocks, algae, meat) is pixel art on a small canvas scaled up. Creatures and
   predators are pixel sprites too, but drawn at smooth sub-pixel positions, rotated to their heading and
   interpolated between ticks, so they swim instead of hopping from cell to cell. */
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var ac = $('arena-cv'); if (!ac) return;
  var ag = ac.getContext('2d'), bc = $('brain-cv'), bg = bc.getContext('2d'), gc = $('gene-cv'), gg = gc.getContext('2d');
  var dpr = Math.min(2, window.devicePixelRatio || 1);
  var WP = 320, WS = 1.6, vents = [], meadows = [], discs = {};
  var wc = document.createElement('canvas'); wc.width = WP; wc.height = WP; var wg = wc.getContext('2d');
  var bgc = null, last = null, net = null, kar = null, hist = [];
  var tpsT = 0, tpsTick = 0, tps = 0, lastFrameT = 0, gap = 33, uiT = 0, toastT = 0, feedT = {};
  var sprites = {}, spriteN = 0, AW = 0, AH = 0, view = { s: 1, ox: 0, oy: 0, k: 1 };
  var pos = {}, predPos = [], hover = null, mouse = null, inspId = 0, view_i = 0, minis = {}, isls = [], sptree = [], ped = null, islT = 0;
  var PAL = [[6, 10, 16], [12, 14, 9], [17, 17, 19], [4, 13, 20], [10, 46, 56], [6, 22, 21], [7, 16, 30], [8, 5, 6]];
  var MEAD = ['rgba(40,120,80,0.55)', 'rgba(90,110,40,0.55)', 'rgba(70,100,85,0.40)', 'rgba(30,150,125,0.60)'], maps = null, ENV = -1, kelpZ = [], caust = null;
  var ISL = [{ n: 'Green Meadows', d: 'plenty of algae' }, { n: 'Toxic Marsh', d: 'strong vents, lots of poison' }, { n: 'Lean Waters', d: 'scarce food' }, { n: 'Rich Shallows', d: 'abundant food' },
    { n: 'Coral Reef', d: 'new: coral shelters you from bites' }, { n: 'Kelp Forest', d: 'new: hide in kelp, swim slowly' }, { n: 'Arctic Ice', d: 'new: cold, big bodies stay warm' }, { n: 'Black Smoker', d: 'new: dark, rich food by deadly heat' }];
  var LEG = [
    [['#50e3c2', 'algae (food)'], ['#c4423f', 'meat (the dead)'], ['#b45cf0', 'poison algae & toxic vents'], ['#287850', 'algae meadow']],
    [['#50e3c2', 'algae (food)'], ['#c4423f', 'meat (the dead)'], ['#b45cf0', 'poison algae & toxic vents'], ['#5a6e28', 'marsh meadow']],
    [['#50e3c2', 'algae (food)'], ['#c4423f', 'meat (the dead)'], ['#b45cf0', 'poison & toxic vent'], ['#8a8f99', 'boulders']],
    [['#50e3c2', 'algae (food)'], ['#c4423f', 'meat (the dead)'], ['#b45cf0', 'poison & toxic vent'], ['#1e9682', 'meadows']],
    [['#bff4ff', 'plankton (food)'], ['#ff6fa8', 'coral: bites near it do half damage'], ['#ff9ad0', 'jellyfish (hurt)'], ['#c4423f', 'meat']],
    [['#8fd14f', 'kelp snails (food)'], ['#3f8f3a', 'kelp: hidden but slow inside'], ['#7a3fa0', 'urchins (hurt)'], ['#c4423f', 'meat']],
    [['#ff9a7a', 'krill (food)'], ['#e6f2f8', 'ice floes'], ['#2fb0a0', 'brine & toxic bloom (hurt)'], ['#c4423f', 'meat']],
    [['#fff2c0', 'tube worms (food)'], ['#ff7a20', 'black smoker: deadly heat'], ['#e8d040', 'sulfur (hurt)'], ['#c4423f', 'meat']]];
  function setLegend() {
    var el = $('legend'); if (!el || ENV < 0) return;
    el.innerHTML = LEG[ENV].map(function (x) { return '<span><i style="background:' + x[0] + '"></i>' + x[1] + '</span>'; }).join('') +
      '<span style="color:#6b6b6b">bodies: paddles = fins (they row) &middot; red blades = spikes (wound on impact) &middot; grey = armor &middot; dark red = mouths &middot; white = eyes</span>';
  }
  var SENS = ['bias', 'plant dir', 'plant near', 'meat dir', 'meat near', 'other dir', 'other near', 'kinship', 'its size', 'its signal',
    'hunter dir', 'hunter near', 'hunter biting', 'wall ahead', 'energy', 'health', 'pain', 'heard', 'poison dir', 'poison near', 'toxic here', 'toxic ahead', 'just ate'];
  var OUTS = ['turn', 'thrust', 'bite', 'signal', 'mate'];
  var LOCI = ['size', 'speed', 'armor', 'attack', 'sight', 'diet', 'hue', 'pattern', 'pattern', 'pattern', 'mutation', 'plasticity', 'rule A', 'rule B', 'rule C', 'rule D', 'mod base', 'fertility', 'choosiness'];
  var LGROUP = [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 3, 3, 3, 3, 3, 3, 4, 4];
  var GROUPS = [{ n: 'body', c: [80, 227, 194] }, { n: 'looks', c: [255, 200, 90] }, { n: 'genetics', c: [120, 255, 140] }, { n: 'learning rule', c: [167, 139, 250] }, { n: 'mating', c: [255, 120, 190] }];
  var TCOL = [[120, 190, 255], [245, 166, 35], [190, 120, 255]];
  var ROLE = { hunter: [255, 90, 90], scavenger: [255, 170, 80], grazer: [80, 227, 194] };

  function rgba(c, a) { return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }
  function hsl(h, s, l, a) { return 'hsla(' + h + ',' + s + '%,' + l + '%,' + (a === undefined ? 1 : a) + ')'; }
  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }
  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function hash(a, b) { var x = Math.imul(a ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(b + 0x632be5ab, 0xc2b2ae35); x ^= x >>> 15; x = Math.imul(x, 0x2c1b3c6d); x ^= x >>> 12; return (x >>> 0) / 4294967296; }
  function role(c) { return c[13] >= 120 ? 'hunter' : c[15] >= 50 ? 'scavenger' : 'grazer'; }
  function pct(a, b) { return b > 0 ? Math.round(100 * a / b) : 0; }

  /* ---------- sizing ---------- */
  function fit(cv, cx, w, h) { cv.width = Math.max(1, Math.round(w * dpr)); cv.height = Math.max(1, Math.round(h * dpr)); cx.setTransform(dpr, 0, 0, dpr, 0, 0); }
  function resize() {
    var a = $('arena'); AW = a.clientWidth; AH = a.clientHeight;
    ac.style.width = AW + 'px'; ac.style.height = AH + 'px'; fit(ac, ag, AW, AH);
    var side = Math.max(160, Math.min(AW - 32, AH - 120));
    view.s = side; view.k = side / WP; view.ox = Math.round((AW - side) / 2); view.oy = Math.round(70 + (AH - 120 - side) / 2);
    fit(bc, bg, bc.clientWidth, bc.clientHeight); fit(gc, gg, gc.clientWidth, gc.clientHeight);
  }
  if (window.ResizeObserver) { var ro = new ResizeObserver(resize); ro.observe($('arena')); ro.observe(bc); ro.observe(gc); } else window.addEventListener('resize', resize);

  /* ---------- the slide: water and rocks, drawn once ---------- */
  function vnoise(x, y, sc) {
    var gx = Math.floor(x / sc), gy = Math.floor(y / sc), fx = x / sc - gx, fy = y / sc - gy;
    var a = hash(gx, gy), b = hash(gx + 1, gy), c = hash(gx, gy + 1), d = hash(gx + 1, gy + 1);
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
  }
  function makeBackground(obst) {
    bgc = document.createElement('canvas'); bgc.width = WP; bgc.height = WP;
    var g = bgc.getContext('2d'), img = g.createImageData(WP, WP), d = img.data, x, y, i;
    for (y = 0; y < WP; y++) for (x = 0; x < WP; x++) {
      i = (y * WP + x) * 4;
      var n = hash(x, y), v = vnoise(x, y, 22), e = ENV < 0 ? view_i % 8 : ENV, pal = PAL[e], b0 = Math.floor(v * 4), spark = n > 0.996 ? 16 : (e === 2 && n > 0.93 ? 5 : 0);
      var r0 = pal[0] + b0 + spark * 0.6, g0 = pal[1] + b0 + spark, bl0 = pal[2] + b0 + spark;
      var sn = vnoise(x + 500, y, 26) * 0.7 + vnoise(x, y + 500, 9) * 0.3 + (n - 0.5) * 0.08;
      if (e === 4 && sn > 0.56) { var sd = 50 + n * 10 + (sn - 0.56) * 60; r0 = sd + 10; g0 = sd + 6; bl0 = sd - 10; }          /* sand */
      else if (e === 5 && n > 0.985) { r0 = 20; g0 = 34; bl0 = 26; }                                                          /* pebbles */
      else if (e === 6) { var st = Math.sin(x * 0.05 + y * 0.02) * 2; r0 += st; g0 += st; bl0 += st * 2; }                   /* cold streaks */
      else if (e === 7 && n > 0.992) { r0 = 70; g0 = 16; bl0 = 10; }                                                          /* embers */
      d[i] = r0; d[i + 1] = g0; d[i + 2] = bl0; d[i + 3] = 255;
    }
    for (var k = 0; k < (obst || []).length; k++) {
      var o = obst[k], cx = o[0] / 1000 * WP, cy = o[1] / 1000 * WP, r = o[2] / 1000 * WP;
      for (y = Math.floor(cy - r - 1); y <= cy + r + 1; y++) for (x = Math.floor(cx - r - 1); x <= cx + r + 1; x++) {
        if (x < 0 || y < 0 || x >= WP || y >= WP) continue;
        var dx = x + 0.5 - cx, dy = y + 0.5 - cy, dd = Math.sqrt(dx * dx + dy * dy);
        if (dd > r) continue;
        i = (y * WP + x) * 4;
        var light = (-dx - dy) / (r * 1.6), e2 = ENV < 0 ? view_i % 8 : ENV, col = obstPix(e2, k, dx, dy, dd, r, light, x, y);
        if (!col) continue;
        d[i] = col[0]; d[i + 1] = col[1]; d[i + 2] = col[2]; d[i + 3] = 255;
      }
    }
    g.putImageData(img, 0, 0);
  }

  /* what an obstacle looks like in each environment: rock, branching coral, ice floe or basalt */
  var CORAL = [[255, 111, 168], [255, 154, 60], [176, 108, 255], [255, 210, 60], [255, 120, 120]];
  function obstPix(e, k, dx, dy, dd, r, light, x, y) {
    var tex = hash(x * 3, y * 7);
    if (e === 4) {
      var a = Math.atan2(dy, dx), br = 0.5 + 0.5 * Math.cos(a * 9 + hash(k, 3) * 6 + dd * 0.9);
      if (dd > r * 0.35 && br < 0.45) return null;                         /* gaps between the branches */
      var c = CORAL[Math.floor(k / 6) % CORAL.length], m = 0.55 + light * 0.35 + (dd / r) * 0.25;
      if (dd > r - 1.6 && tex > 0.55) return [255, 236, 242];               /* polyps at the tips */
      return [Math.min(255, c[0] * m), Math.min(255, c[1] * m), Math.min(255, c[2] * m)];
    }
    if (e === 6) {
      var an = Math.atan2(dy, dx), edge = r * (0.86 + 0.14 * vnoise(an * 9 + k * 13, k * 7, 1.3));
      if (dd > edge) return dd > edge + 0.5 && dd < r ? [30, 70, 100] : null;          /* the shelf under the water */
      if (dd > edge - 1.3) return [120, 185, 215];
      var crackLine = Math.abs(vnoise(x * 0.9 + k * 40, y * 0.9, 9) - 0.5) < 0.025;
      if (crackLine) return [140, 185, 212];
      if (tex > 0.93) return [255, 255, 255];
      var w = 205 + light * 40 + tex * 6; return [w - 10, w, Math.min(255, w + 12)];
    }
    if (e === 7) {
      if (tex > 0.965) return [200, 60, 20];                                 /* glowing cracks */
      var l7 = dd > r - 1.2 ? 14 : 24 + light * 14 + tex * 6; return [l7, l7 * 0.9, l7 * 0.92];
    }
    if (e === 5) { var l5 = dd > r - 1.2 ? 16 : 30 + light * 16 + tex * 8; return [l5 * 0.75, l5, l5 * 0.85]; }
    var l = dd > r - 1.2 ? 22 : 36 + light * 20 + tex * 9;
    return [l * 0.82, l * 0.88, l];
  }

  /* reef caustics: four frames of rippling sunlight, computed once */
  function caustics() {
    if (caust) return caust;
    caust = [];
    for (var f = 0; f < 4; f++) {
      var cv = document.createElement('canvas'); cv.width = WP; cv.height = WP;
      var g = cv.getContext('2d'), img = g.createImageData(WP, WP), d = img.data, ph = f * 1.5708;
      for (var y = 0; y < WP; y++) for (var x = 0; x < WP; x++) {
        var v = Math.sin(x * 0.21 + ph) + Math.sin(y * 0.19 - ph * 1.3) + Math.sin((x + y) * 0.13 + ph * 0.7);
        if (Math.abs(v) < 0.2) { var i = (y * WP + x) * 4; d[i] = 220; d[i + 1] = 250; d[i + 2] = 255; d[i + 3] = 34; }
      }
      g.putImageData(img, 0, 0); caust.push(cv);
    }
    return caust;
  }

  /* things drawn in front of the creatures: kelp they hide in, falling snow, smoke */
  var oc = document.createElement('canvas'); oc.width = WP; oc.height = WP; var og = oc.getContext('2d');
  function drawFront(now) {
    og.clearRect(0, 0, WP, WP);
    var i, j, k;
    if (ENV === 5) {
      for (i = 0; i < kelpZ.length; i++) {
        var zx = kelpZ[i][0] / 1000 * WP, zy = kelpZ[i][1] / 1000 * WP, zr = kelpZ[i][2] / 1000 * WP, ns = Math.round(zr * 0.55);
        for (j = 0; j < ns; j++) {
          var a = hash(i * 31 + j, 5) * 6.2832, rr = Math.sqrt(hash(j, i * 7 + 1)) * zr * 0.9, bx = zx + Math.cos(a) * rr, by = zy + Math.sin(a) * rr * 0.8 + zr * 0.35;
          var h = zr * (0.7 + hash(j, i) * 0.8);
          for (k = 0; k < h; k++) {
            var u = k / h, sx = bx + Math.sin(now / 900 + j * 1.7 + k * 0.12) * u * 3.2, sy = by - k;
            og.fillStyle = (k & 2) ? 'rgba(63,143,58,0.88)' : 'rgba(84,170,64,0.88)'; og.fillRect(Math.round(sx), Math.round(sy), 1, 1);
            if (k % 5 === 2) { var side = (k / 5) & 1 ? 1 : -1; og.fillStyle = 'rgba(120,200,80,0.8)'; og.fillRect(Math.round(sx + side), Math.round(sy), 1, 1); og.fillRect(Math.round(sx + side * 2), Math.round(sy - 1), 1, 1); }
          }
          og.fillStyle = 'rgba(160,230,110,0.9)'; og.fillRect(Math.round(bx + Math.sin(now / 900 + j * 1.7 + h * 0.12) * 3.2), Math.round(by - h), 1, 1);
        }
      }
    }
    if (ENV === 6) {
      for (i = 0; i < 150; i++) {
        var sx2 = (hash(i, 1) * WP + Math.sin(now / 1300 + i) * 4 + now * 0.004) % WP, sy2 = (hash(i, 2) * WP + now * (0.008 + hash(i, 3) * 0.01)) % WP;
        og.fillStyle = 'rgba(240,248,255,' + (0.45 + hash(i, 4) * 0.45) + ')'; og.fillRect(Math.round(sx2), Math.round(sy2), hash(i, 5) > 0.85 ? 2 : 1, 1);
      }
    }
    if (ENV === 7) {
      for (i = 0; i < vents.length; i++) {
        var vx = vents[i][0] / 1000 * WP, vy = vents[i][1] / 1000 * WP, vr = vents[i][2] / 1000 * WP, top = vy - vr * 0.9;
        for (j = 0; j < 16; j++) {
          var p = ((now / 2600) + j / 16) % 1, px = vx + Math.sin(p * 5 + j * 2.1) * p * 7, py = top - p * vr * 2.8, pr = Math.round(1 + p * 4);
          og.globalAlpha = 0.7 * (1 - p); og.drawImage(disc(pr, 'rgba(28,24,26,1)', 0.9, 'smoke' + pr), Math.round(px - pr), Math.round(py - pr)); og.globalAlpha = 1;
        }
      }
    }
  }

  /* a dithered pixel disc, used for algae meadows and toxic vents */
  function disc(rpx, col, dens, key) {
    if (discs[key]) return discs[key];
    var n = Math.ceil(rpx) * 2 + 2, cv = document.createElement('canvas'); cv.width = n; cv.height = n;
    var g = cv.getContext('2d'), c = n / 2;
    for (var y = 0; y < n; y++) for (var x = 0; x < n; x++) {
      var d = Math.sqrt((x + 0.5 - c) * (x + 0.5 - c) + (y + 0.5 - c) * (y + 0.5 - c)) / rpx;
      if (d > 1) continue;
      var p = dens * Math.pow(1 - d, 0.6);
      if (hash(x * 5 + key.length, y * 3) < p) { g.fillStyle = col; g.fillRect(x, y, 1, 1); }
    }
    return (discs[key] = cv);
  }

  /* ---------- microbe sprites: built from the genes, two animation frames, cached ----------
       body size and shape: size, speed (fast bodies are longer)     shading and pattern: hue, pattern genes
       grey plates: armor     spikes: attack (red if it eats meat)     eye: sight     nucleus: brain size
       cilia (slow bodies) or a whip tail (fast bodies, drawn live)    the sprite faces +x */
  function spriteKey(c) {
    return [Math.min(60, Math.round(c[10] / 8)), Math.round(c[11] / 25), Math.round(c[12] / 25), Math.round(c[13] / 25), Math.round(c[14] / 8), Math.round(c[15] / 34),
      Math.round(c[16] / 10), Math.round(c[17] / 10), Math.round(c[18] / 10), Math.round(c[3] / 12), Math.min(4, Math.floor(c[26] / 5))].join('.');
  }
  function buildSprite(c) {
    var size = c[10] / 100, speed = c[11] / 100, armor = c[12] / 100, attack = c[13] / 100, sight = c[14] / 100, diet = c[15] / 100;
    var p1 = c[16] / 100, p2 = c[17] / 100, p3 = c[18] / 100, hue = c[3], nn = c[26];
    var n = Math.min(41, Math.max(5, 9 + 2 * Math.round((size - 0.6) * 3))), W = n + 8, H = n + 6;   /* genes are unbounded now; sprites stop growing at 41 px */
    var cx = W / 2 - 1, cy = H / 2, rx = n / 2 * (0.9 + 0.25 * (speed - 0.5)), ry = n / 2 * (0.95 - 0.15 * (speed - 0.5));
    var seed = Math.round(p1 * 10) * 131 + Math.round(p2 * 10) * 17 + Math.round(p3 * 10);
    var lite = hsl(hue, 70, 64), body = hsl(hue, 58, 47), deep = hsl(hue, 62, 34), memb = hsl(hue, 70, 18);
    var acc1 = hsl((hue + 30 + p2 * 200) % 360, 70, 60), acc2 = hsl((hue + 30 + p2 * 200) % 360, 60, 44);
    var mode = Math.min(2, Math.floor(p3 * 3)), frames = [], f, x, y, k;
    function inside(x, y) { var dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry; return dx * dx + dy * dy <= 1; }
    for (f = 0; f < 2; f++) {
      var cv = document.createElement('canvas'); cv.width = W; cv.height = H;
      var g = cv.getContext('2d');
      var px = function (x, y, col) { g.fillStyle = col; g.fillRect(x, y, 1, 1); };
      if (speed <= 1.1) {
        var nc = 10 + Math.round(size * 4);
        for (k = 0; k < nc; k++) {
          var a = (k + f * 0.5) / nc * 6.2832;
          if (Math.cos(a) > 0.75) continue;
          px(Math.round(cx + Math.cos(a) * (rx + 1.2) - 0.5), Math.round(cy + Math.sin(a) * (ry + 1.2) - 0.5), hsl(hue, 50, 70, 0.75));
        }
      }
      for (y = 0; y < H; y++) for (x = 0; x < W; x++) {
        if (!inside(x, y)) continue;
        var edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
        var dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry, r2 = dx * dx + dy * dy, h1 = hash(seed + x * 7, y * 13);
        var shade = -dx * 0.45 - dy * 0.75, col = shade > 0.45 ? lite : shade < -0.35 ? deep : body;
        if (mode === 0 && h1 < 0.08 + p1 * 0.25 && r2 < 0.7) col = shade < 0 ? acc2 : acc1;
        else if (mode === 1 && Math.floor((y + p1 * 5) / 2) % 2 === 0 && r2 < 0.8) col = shade < 0 ? acc2 : acc1;
        else if (mode === 2 && h1 > 0.9 - p1 * 0.1) col = lite;
        if (edge) col = memb;
        var ang = Math.atan2(dy, dx), cover = armor > 1.0 ? 1.2 : armor > 0.6 ? 0.55 : 0.1;
        if (armor > 0.3 && r2 > 0.5 && -Math.sin(ang) > -cover && Math.cos(ang) < 0.85) {
          var seg = Math.floor((ang + 3.1416) / (6.2832 / (6 + Math.round(armor * 4))));
          col = edge ? '#4a5262' : (seg % 2 ? '#b9c4d4' : '#8c98ab');
        }
        px(x, y, col);
      }
      var nr = 0.9 + Math.min(4, nn / 6) * 0.45, ncx = cx - rx * 0.28;
      for (y = 0; y < H; y++) for (x = 0; x < W; x++) {
        var ddx = x + 0.5 - ncx, ddy = y + 0.5 - cy;
        if (ddx * ddx + ddy * ddy <= nr * nr && inside(x, y)) px(x, y, ddx < 0 && ddy < 0 ? hsl(hue + 180, 30, 34) : hsl(hue + 180, 35, 20));
      }
      var ns = Math.min(9, Math.round(attack * 2.2)), spk = diet > 0.5 ? '#ff4b3a' : '#e8ecf2', tip = diet > 0.5 ? '#ffb199' : '#ffffff', fx = Math.round(cx + rx);
      for (k = 0; k < ns; k++) {
        var sy = Math.round(cy + (k - (ns - 1) / 2) * 2.2), len = 1 + Math.min(6, Math.round(attack * 1.2)) - (Math.abs(k - (ns - 1) / 2) > 1 ? 1 : 0) + (f && k % 2 ? 1 : 0);
        for (var j = 0; j < len; j++) px(fx + j, sy, j === len - 1 ? tip : spk);
      }
      var ex = Math.round(cx + rx * 0.42), ey = Math.round(cy - ry * 0.38);
      if (sight > 0.28) { px(ex, ey - 1, '#f2f6ff'); px(ex + 1, ey - 1, '#f2f6ff'); px(ex, ey, '#f2f6ff'); px(ex + 1, ey, diet > 0.5 ? '#d01010' : '#05060a'); }
      else { px(ex, ey, '#f2f6ff'); px(ex + 1, ey, diet > 0.5 ? '#d01010' : '#05060a'); }
      frames.push(cv);
    }
    return { cv: frames, w: W, h: H, cx: cx + 0.5, cy: cy, rx: rx, tail: cx - rx, whip: speed > 1.1 };
  }
  function spriteOf(c) {
    var k = spriteKey(c), s = sprites[k];
    if (!s) { if (spriteN > 1500) { sprites = {}; spriteN = 0; } s = sprites[k] = buildSprite(c); spriteN++; }
    return s;
  }
  /* the predator: a big red amoeba with teeth, two frames */
  var predSpr = (function () {
    var out = [];
    for (var f = 0; f < 2; f++) {
      var cv = document.createElement('canvas'); cv.width = 21; cv.height = 21; var g = cv.getContext('2d');
      for (var y = 0; y < 21; y++) for (var x = 0; x < 21; x++) {
        var dx = x - 10, dy = y - 10, a = Math.atan2(dy, dx), r = 7.2 + Math.sin(a * 5 + f * 1.3) * 1.3, d = Math.sqrt(dx * dx + dy * dy);
        if (d > r) continue;
        g.fillStyle = d > r - 1 ? '#5a0f14' : (-dx - dy > 4 ? '#ff6b5e' : '#d8322f'); g.fillRect(x, y, 1, 1);
      }
      g.fillStyle = '#fff'; g.fillRect(12, 7, 2, 2); g.fillRect(12, 12, 2, 2); g.fillStyle = '#000'; g.fillRect(13, 8, 1, 1); g.fillRect(13, 13, 1, 1);
      g.fillStyle = '#fff'; for (var t = 0; t < 3; t++) g.fillRect(16, 8 + t * 2, 1 + (f ? 1 : 0), 1);
      out.push(cv);
    }
    return out;
  })();

  /* ---------- frames ---------- */
  window.SwEvents = window.SwEvents || {};
  window.SwEvents.frame = function (d) {
    var now = performance.now(), i;
    if (d.isl !== undefined && d.isl !== view_i) return;   /* someone else is watching another island */
    if (d.maps) maps = d.maps;
    if (d.envs) { var ch = envOf.join() !== d.envs.join(); envOf = d.envs; if (ch) { var el0 = $('isls'); if (el0) el0.innerHTML = ''; } }
    if (d.env !== undefined && d.env !== ENV) { ENV = d.env; bgc = null; setLegend(); }
    if (d.obst && !bgc) makeBackground(d.obst);
    if (d.ws) WS = d.ws;
    if (d.vents) vents = d.vents;
    if (d.meadows) meadows = d.meadows;
    if (d.kelp) kelpZ = d.kelp;
    if (d.env !== undefined && d.env !== ENV) { ENV = d.env; bgc = null; setLegend(); }
    if (last && d.tick < last.tick) { pos = {}; hist = []; }
    if (lastFrameT) gap = gap * 0.8 + clamp(now - lastFrameT, 8, 400) * 0.2;
    lastFrameT = now;
    /* interpolation: start each creature from where it is drawn now, glide to the new position */
    var seen = {};
    for (i = 0; i < d.cr.length; i++) {
      var c = d.cr[i], id = c[1], x = c[4] / 1000, y = c[5] / 1000, a = Math.atan2(c[7], c[6]), p = pos[id];
      seen[id] = 1;
      var bd = c[30] || [], nb = []; for (var q = 0; q + 4 < bd.length; q += 5) nb.push([bd[q + 3] / 1000, bd[q + 4] / 1000]);
      if (p && p.b1 && p.b1.length === nb.length) { p.b0 = atBody(p, now); p.b1 = nb; } else if (p) { p.b0 = nb; p.b1 = nb; }
      if (!p) pos[id] = { x0: x, y0: y, a0: a, x1: x, y1: y, a1: a, t: now, born: now, b0: nb, b1: nb };
      else { var cur = at(p, now); p.x0 = cur[0]; p.y0 = cur[1]; p.a0 = cur[2]; p.x1 = x; p.y1 = y; p.a1 = a; p.t = now; }
    }
    for (var k in pos) if (!seen[k]) delete pos[k];
    for (i = 0; i < d.preds.length; i++) {
      var q = predPos[i], px = d.preds[i][0] / 1000, py = d.preds[i][1] / 1000;
      if (!q) predPos[i] = { x0: px, y0: py, x1: px, y1: py, t: now };
      else { var u = clamp((now - q.t) / gap, 0, 1); q.x0 = q.x0 + (q.x1 - q.x0) * u; q.y0 = q.y0 + (q.y1 - q.y0) * u; q.x1 = px; q.y1 = py; q.t = now; }
    }
    last = d;
    minis[d.isl] = { cr: d.cr.map(function (c) { return [c[4], c[5], c[3]]; }), tick: d.tick };
    if (d.isls) isls = d.isls;
    if (d.sptree) sptree = d.sptree;
    if (d.ped) ped = d.ped;
    if (d.net) net = d.net;
    if (d.kar) kar = d.kar;
    if (d.hist) hist = d.hist;
    if (now - tpsT > 1000) { if (tpsT) tps = Math.max(0, (d.tick - tpsTick) * 1000 / (now - tpsT)); tpsT = now; tpsTick = d.tick; }
    for (i = 0; i < d.evs.length; i++) addFeed(d.evs[i], now);
    if (now - uiT > 250) { uiT = now; updateUI(d); }
  };
  window.SwEvents.mini = function (d) { minis[d.isl] = d; };
  function atBody(p, now) {
    var u = clamp((now - p.t) / gap, 0, 1), out = [], a = p.b0 || p.b1, b = p.b1;
    for (var i = 0; i < b.length; i++) { var q = a[i] || b[i]; out.push([q[0] + (b[i][0] - q[0]) * u, q[1] + (b[i][1] - q[1]) * u]); }
    return out;
  }
  function at(p, now) {
    var u = clamp((now - p.t) / gap, 0, 1), da = p.a1 - p.a0;
    while (da > Math.PI) da -= 6.2832; while (da < -Math.PI) da += 6.2832;
    return [p.x0 + (p.x1 - p.x0) * u, p.y0 + (p.y1 - p.y0) * u, p.a0 + da * u];
  }
  function rowOf(slot) { if (!last) return null; for (var i = 0; i < last.cr.length; i++) if (last.cr[i][0] === slot) return last.cr[i]; return null; }
  function rowById(id) { if (!last) return null; for (var i = 0; i < last.cr.length; i++) if (last.cr[i][1] === id) return last.cr[i]; return null; }

  /* ---------- the story page ---------- */
  function updateUI(d) {
    var nsp = d.sps.filter(function (s) { return s[1] > 0; }).length, nnb = d.pop ? d.nn / d.pop : 0;
    var head = $('head');
    if (head) head.innerHTML = '<span class="big">' + islName(view_i) + ' &middot; gen ' + fmtc(d.cr.reduce(function (m, c) { return Math.max(m, c[22]); }, 0)) + '</span><b>' + d.pop + '</b> alive &middot; <b>' + nsp + '</b> species &middot; <b>' + nnb.toFixed(1) + '</b> neurons per brain &middot; <b>' + (d.mig_in || 0) + '</b> migrants arrived';
    var o = $('o-tps'); if (o) o.textContent = Math.round(tps);
    var op = $('o-procs'); if (op) op.textContent = fmtc(d.nn);
    var ck = $('o-ck'); if (ck) { var ago = d.tick - d.ck_tick; ck.textContent = d.ck ? 'saved ' + (tps > 0 ? Math.round(ago / tps) + 's ago' : 'just now') : 'not saved yet'; }
    var sb = document.querySelectorAll('[data-speed]'); for (var i = 0; i < sb.length; i++) sb[i].classList.toggle('on', Number(sb[i].getAttribute('data-speed')) === Math.max(1, d.speed));
    tog('b-plast', 'Learning: ', d.plast);
    insights(d, nnb); runCharts(d, nnb); speciesList(d); islandTiles(); drawTree();
    var isub = $('ins-sub'); if (isub) isub.textContent = 'on ' + islName(view_i);
    if (inspId) inspector(d);
  }
  function tog(id, label, on) { var b = $(id); if (b) { b.textContent = label + (on ? 'on' : 'off'); b.classList.toggle('on', !!on); } }

  function tile(v, t, desc, col) { return '<div class="tile"><div class="v" style="color:' + col + '">' + v + '</div><div class="t">' + t + '</div><div class="d">' + desc + '</div></div>'; }
  function insights(d, nnb) {
    var el = $('ins'); if (!el) return;
    var deaths = d.d_starve + d.d_pred + d.d_eaten + d.d_old + (d.d_toxic || 0), births = d.b_sex + d.b_bud, h = '';
    if (deaths < 20) h += tile('&ndash;', 'Too early to tell', 'Wait for a few dozen deaths.', '#8f8f8f');
    else if (d.d_eaten > d.d_starve) h += tile(pct(d.d_eaten, deaths) + '%', 'They eat each other', 'of all deaths: eaten by another creature. ' + pct(d.d_starve, deaths) + '% starved, ' + pct(d.d_toxic || 0, deaths) + '% died of toxins.', '#ff6b6b');
    else h += tile(pct(d.d_starve, deaths) + '%', 'Hunger rules', 'of all deaths were starvation; ' + pct(d.d_eaten, deaths) + '% were eaten by other creatures.', '#f5a623');
    if (births < 20) h += tile('&ndash;', 'Sex or cloning?', 'Not enough births yet.', '#8f8f8f');
    else if (d.b_sex >= d.b_bud) h += tile(pct(d.b_sex, births) + '%', 'Sex beats cloning', 'of births had two parents. Budding (cloning yourself) is allowed but costs more.', '#ff78be');
    else h += tile(pct(d.b_bud, births) + '%', 'Cloning beats sex', 'of births were budding: finding a compatible mate is too hard here.', '#ff78be');
    h += tile(nnb.toFixed(1), nnb > 6 ? 'Brains grew' : 'Brains stay small', 'neurons per brain. Founders had 5, and every extra neuron costs energy every tick.', '#5aa9ff');
    var eta = d.mean[7] / 1000, r = eta / 0.04;
    h += tile(r.toFixed(1) + '&times;', r > 1.3 ? 'Learning is favoured' : r < 0.7 ? 'Learning is fading' : 'Learning holds steady', 'lifetime learning rate vs the founders. The rule evolves; what is learned is not inherited.', '#a78bfa');
    el.innerHTML = h;
  }

  var MINI = [{ n: 'Foraging', u: 'meals / 1000 ticks', k: 3, f: 100, c: [80, 227, 194], dp: 1 }, { n: 'Brain size', u: 'neurons', k: 4, f: 100, c: [90, 170, 255], dp: 1 },
    { n: 'Attack', u: 'gene', k: 5, f: 100, c: [255, 90, 90], dp: 2 }, { n: 'Learning rate', u: 'gene', k: 6, f: 1000, c: [167, 139, 250], dp: 3 },
    { n: 'Population', u: 'alive', k: 2, f: 1, c: [237, 237, 237], dp: 0 }, { n: 'Species', u: 'alive', k: 9, f: 1, c: [255, 200, 90], dp: 0 },
    { n: 'Fleeing hunters', u: '(+1 away, 0 random)', k: 11, f: 1000, c: [120, 255, 140], dp: 2 }, { n: 'Eaten', u: 'per 1000 ticks per creature', k: 12, f: 100, c: [255, 90, 160], dp: 2 }];
  function runCharts(d, nnb) {
    var el = $('sm'); if (!el) return;
    if (!el.children.length) el.innerHTML = MINI.map(function (m, i) { return '<div><div class="k"><span>' + m.n + '</span><b id="mv' + i + '"></b></div><canvas id="mc' + i + '"></canvas></div>'; }).join('');
    var live = [d.tick, d.maxgen, d.pop, d.forage, Math.round(nnb * 100), d.mean[3], d.mean[7], d.mean[0], d.mean[2], d.sps.filter(function (s) { return s[1] > 0; }).length, d.mean[5]];
    var series = hist.slice().reverse();
    if (series.length && series[series.length - 1].length >= 13) { live = live.concat(series[series.length - 1].slice(11, 13)); series = series.concat([live]); }
    else series = series.concat([live]);
    for (var i = 0; i < MINI.length; i++) {
      var m = MINI[i], vals = series.filter(function (r) { return r.length > m.k; }).map(function (r) { return r[m.k] / m.f; }), cur = vals[vals.length - 1], first = vals[0];
      var mv = $('mv' + i); if (mv && !vals.length) mv.innerHTML = '<span style="color:#6b6b6b;font-weight:400">collecting</span>'; else if (mv) { var dl = cur - first, arrow = vals.length < 2 || Math.abs(dl) < 1e-9 ? '' : (dl > 0 ? ' &uarr;' : ' &darr;'); mv.innerHTML = cur.toFixed(m.dp) + '<span style="color:#6b6b6b;font-weight:400"> ' + m.u + arrow + '</span>'; }
      spark($('mc' + i), vals, m.c);
    }
    var rs = $('run-span'); if (rs && series.length > 1) rs.textContent = 'generation ' + fmtc(series[0][1]) + ' to ' + fmtc(d.maxgen);
    var rn = $('run-note'); if (rn) rn.textContent = hist.length < 2 ? 'One sample every 500 ticks; the history is saved with the checkpoint. Use turbo to fill it faster.' : hist.length + ' samples, one every 500 ticks, saved with the checkpoint.';
  }
  function spark(cv, vals, col) {
    if (!cv) return;
    var w = cv.clientWidth, h = cv.clientHeight; if (cv.width !== Math.round(w * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    var g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, w, h);
    if (vals.length < 2) { g.fillStyle = '#1a1a1a'; g.fillRect(0, h - 2, w, 1); return; }
    var lo = Math.min.apply(null, vals), hi = Math.max.apply(null, vals); if (hi - lo < 1e-9) { hi = lo + 1; lo -= 1; }
    var X = function (i) { return i / (vals.length - 1) * (w - 4) + 2; }, Y = function (v) { return h - 3 - (v - lo) / (hi - lo) * (h - 8); };
    var gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, rgba(col, 0.28)); gr.addColorStop(1, rgba(col, 0));
    g.beginPath(); g.moveTo(X(0), h); for (var i = 0; i < vals.length; i++) g.lineTo(X(i), Y(vals[i])); g.lineTo(X(vals.length - 1), h); g.closePath(); g.fillStyle = gr; g.fill();
    g.beginPath(); for (i = 0; i < vals.length; i++) { if (i === 0) g.moveTo(X(i), Y(vals[i])); else g.lineTo(X(i), Y(vals[i])); } g.strokeStyle = rgba(col, 1); g.lineWidth = 1.6; g.stroke();
    g.fillStyle = rgba(col, 1); g.beginPath(); g.arc(X(vals.length - 1), Y(vals[vals.length - 1]), 2.5, 0, 6.2832); g.fill();
  }

  function speciesList(d) {
    var el = $('spl'); if (!el) return;
    var top = d.sps.filter(function (s) { return s[1] > 0; }).sort(function (a, b) { return b[1] - a[1]; }).slice(0, 6), h = '', reps = [];
    for (var i = 0; i < top.length; i++) {
      var sid = top[i][0], best = null, roles = { hunter: 0, scavenger: 0, grazer: 0 };
      for (var j = 0; j < d.cr.length; j++) { var c = d.cr[j]; if (c[2] !== sid) continue; roles[role(c)]++; if (!best || c[23] > best[23]) best = c; }
      var main = 'grazer'; for (var r in roles) if (roles[r] > roles[main]) main = r;
      reps.push(best);
      h += '<div class="spr" data-id="' + (best ? best[1] : 0) + '"><canvas width="24" height="24" id="spi' + i + '"></canvas><div><div><span class="n">Species #' + sid + '</span> <span class="r">&middot; mostly ' + main + 's</span></div>' +
        '<div class="bar" style="margin-top:5px"><i style="width:' + Math.max(4, pct(top[i][1], d.pop)) + '%;background:' + hsl(top[i][2], 65, 55) + '"></i></div></div><div class="r" style="text-align:right">' + top[i][1] + ' alive</div></div>';
    }
    el.innerHTML = h || '<span style="color:#666;font-size:12px">no species yet</span>';
    for (i = 0; i < reps.length; i++) if (reps[i]) icon($('spi' + i), reps[i]);
  }
  function icon(cv, c) {
    if (c[30] && c[30].length >= 5) return iconMesh(cv, c);
    return iconSprite(cv, c);
  }
  function iconMesh(cv, c) {
    var g = cv.getContext('2d'), bd = c[30], n = bd.length / 5, mnx = 1e9, mny = 1e9, mxx = -1e9, mxy = -1e9, i;
    g.clearRect(0, 0, cv.width, cv.height);
    for (i = 0; i < n; i++) { var x = bd[i * 5 + 3], y = bd[i * 5 + 4], r = bd[i * 5 + 1] / 10000 / WS * 1000; mnx = Math.min(mnx, x - r); mny = Math.min(mny, y - r); mxx = Math.max(mxx, x + r); mxy = Math.max(mxy, y + r); }
    var sc = (cv.width - 2) / Math.max(1, Math.max(mxx - mnx, mxy - mny)), ox = (cv.width - (mxx - mnx) * sc) / 2, oy = (cv.height - (mxy - mny) * sc) / 2;
    var X = function (i) { return ox + (bd[i * 5 + 3] - mnx) * sc; }, Y = function (i) { return oy + (bd[i * 5 + 4] - mny) * sc; };
    g.strokeStyle = hsl(c[3], 50, 35); g.lineWidth = 1;
    for (i = 1; i < n; i++) { var pi = bd[i * 5 + 2]; g.beginPath(); g.moveTo(X(pi), Y(pi)); g.lineTo(X(i), Y(i)); g.stroke(); }
    var TC = { 6: hsl(c[3], 60, 50), 0: hsl(c[3], 60, 62), 1: '#c8323a', 2: '#a9b4c4', 3: hsl(c[3] + 40, 75, 66), 4: '#7a1822', 5: '#f2f6ff' };
    for (i = 0; i < n; i++) { g.fillStyle = TC[bd[i * 5]] || '#888'; var rr = Math.max(1, bd[i * 5 + 1] / 10000 / WS * 1000 * sc); g.beginPath(); g.arc(X(i), Y(i), rr, 0, 6.2832); g.fill(); }
  }
  function iconSprite(cv, c) {
    if (!cv) return;
    var s = spriteOf(c), g = cv.getContext('2d'); g.clearRect(0, 0, cv.width, cv.height); g.imageSmoothingEnabled = false;
    g.drawImage(s.cv[0], Math.round((cv.width - s.w) / 2), Math.round((cv.height - s.h) / 2));
  }

  function toast(t) { var el = $('toast'); if (!el) return; el.textContent = t; el.classList.add('show'); clearTimeout(toastT); toastT = setTimeout(function () { el.classList.remove('show'); }, 2600); }
  function addFeed(e, now) {
    var code = e[0], txt = null, col = '#888';
    if (code === 9) { txt = 'A new species split off: <b>#' + e[3] + '</b>'; col = hsl(e[2], 70, 55); }
    else if (code === 10) { txt = 'Species #' + e[3] + ' died out'; col = '#555'; }
    else if (code === 6) { txt = 'A creature was eaten by another one (generation ' + fmtc(e[3]) + ')'; col = '#ff5a5a'; }
    else if (code === 14) { txt = 'A creature swam off to ' + islName(e[4]); col = '#5aa9ff'; }
    else if (code === 15) { txt = 'A migrant arrived from ' + islName(e[4]); col = '#5aa9ff'; }
    else if (code === 13) { txt = 'Killed by toxins (vent or poison algae)'; col = '#b45cf0'; }
    else if (code === 8 && e[5] >= 3) { txt = 'Died of old age, leaving ' + e[5] + ' children'; col = '#8f8f8f'; }
    else if (code === 7 && e[4] === 1 && Math.random() < 0.15) { txt = 'Born of two parents, ' + e[5] + ' neurons'; col = '#ff78be'; }
    else if (code === 11) { txt = 'Checkpoint saved (' + e[4] + ' genomes)'; col = '#50e3c2'; toast('Checkpoint saved'); }
    else if (code === 12) { txt = 'Resumed from checkpoint at generation ' + fmtc(e[3]); col = '#50e3c2'; toast('Resumed from checkpoint'); }
    if (!txt) return;
    if (code !== 9 && code !== 10 && code < 11) { if (now - (feedT[code] || 0) < 2500) return; feedT[code] = now; }
    var el = $('feed'); if (!el) return;
    var row = document.createElement('div'); row.className = 'ev';
    row.innerHTML = '<i style="background:' + col + '"></i><span>' + txt + '</span>';
    el.insertBefore(row, el.firstChild); while (el.children.length > 6) el.removeChild(el.lastChild);
  }

  /* ---------- the islands ---------- */
  function nIsl() { return isls.length || 4; }
  var envOf = []; function eo(i) { return envOf[i] !== undefined ? envOf[i] : i % 8; }
  function islName(i) {
    var same = envOf.length > 1 && envOf.every(function (e) { return e === envOf[0]; });
    if (same) return ISL[eo(i)].n + ' ' + (i + 1);
    return ISL[eo(i)].n + (nIsl() > 8 ? ' ' + (Math.floor(i / 8) + 1) : '');
  }
  function islandTiles() {
    var el = $('isls'); if (!el) return;
    var n = nIsl();
    if (el.children.length !== n) {
      el.classList.toggle('many', n > 4);
      var h = ''; for (var q = 0; q < n; q++) h += '<div class="it" data-isl="' + q + '"><canvas id="ic' + q + '" width="96" height="96"></canvas><div class="nm">' + islName(q) + '</div><div class="st" id="is' + q + '">' + ISL[eo(q)].d + '</div></div>';
      el.innerHTML = h;
    }
    for (var i = 0; i < n; i++) {
      var t = el.children[i]; t.classList.toggle('on', i === view_i);
      var sm = isls[i], st = $('is' + i);
      if (st && sm && sm.length) st.innerHTML = n > 4 ? sm[1] + ' alive &middot; ' + sm[2] + ' sp' : sm[1] + ' alive &middot; ' + sm[2] + ' species';
      var cv = $('ic' + i); if (!cv) continue;
      var g = cv.getContext('2d'), W = cv.width, m = minis[i];
      var pl = PAL[eo(i)]; g.fillStyle = 'rgb(' + (pl[0] + 2) + ',' + (pl[1] + 2) + ',' + (pl[2] + 2) + ')'; g.fillRect(0, 0, W, W);
      var mp = maps && maps[eo(i)], te = eo(i);
      if (mp) {
        if (mp[2]) for (var kz = 0; kz < mp[2].length; kz++) { g.fillStyle = 'rgba(70,150,60,0.6)'; g.beginPath(); g.arc(mp[2][kz][0] / 1000 * W, mp[2][kz][1] / 1000 * W, mp[2][kz][2] / 1000 * W, 0, 6.2832); g.fill(); }
        for (var o = 0; o < mp[0].length; o++) { g.fillStyle = te === 4 ? 'rgba(255,120,170,0.85)' : te === 6 ? 'rgba(225,240,250,0.9)' : 'rgba(120,128,140,0.7)'; g.beginPath(); g.arc(mp[0][o][0] / 1000 * W, mp[0][o][1] / 1000 * W, mp[0][o][2] / 1000 * W, 0, 6.2832); g.fill(); }
        for (var v = 0; v < mp[1].length; v++) { g.fillStyle = te === 7 ? 'rgba(255,120,40,0.8)' : te === 6 ? 'rgba(40,150,150,0.8)' : te === 4 ? 'rgba(255,160,210,0.7)' : 'rgba(160,70,210,0.65)'; g.beginPath(); g.arc(mp[1][v][0] / 1000 * W, mp[1][v][1] / 1000 * W, mp[1][v][2] / 1000 * W, 0, 6.2832); g.fill(); }
      }
      if (m) for (var k = 0; k < m.cr.length; k++) { g.fillStyle = hsl(m.cr[k][2], 70, 58); g.fillRect(Math.round(m.cr[k][0] / 1000 * W) - 1, Math.round(m.cr[k][1] / 1000 * W) - 1, 2, 2); }
    }
  }
  var switchT = 0;
  function adoptIsland(i) { ENV = -1; kelpZ = []; view_i = i; pos = {}; hist = []; sptree = []; net = null; kar = null; ped = null; bgc = null; vents = []; meadows = []; if (inspId) closeInsp(); }
  function switchIsland(i) {
    if (i === view_i) return;
    switchT = performance.now();
    ENV = -1; kelpZ = [];
    view_i = i; pos = {}; hist = []; sptree = []; net = null; kar = null; ped = null; last = null; bgc = null; vents = []; meadows = [];
    closeInsp(); window.swSend('view', { i: i, fresh: 1 });
    var f = $('feed'); if (f) f.innerHTML = '';
  }

  /* ---------- the species tree of this island ---------- */
  function drawTree() {
    var cv = $('tree-cv'); if (!cv || !last) return;
    var w = cv.clientWidth, h = cv.clientHeight; if (cv.width !== Math.round(w * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    var g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, w, h);
    var t1 = last.tick, ids = {}, i;
    for (i = 0; i < sptree.length; i++) ids[sptree[i][0]] = 1;
    /* a species whose parent is a known species split off here; anything else arrived from outside */
    var all = sptree.map(function (r) { return { r: r, split: !!ids[r[1]], life: (r[4] === 0 ? t1 : r[4]) - r[3] }; });
    var keep = all.filter(function (x) { return x.r[4] === 0 || x.life >= 600; }), hidden = all.length - keep.length;
    var rows = keep.slice(0, 32).reverse(), legend = $('tree-note');
    if (!rows.length) { g.fillStyle = '#5f5f5f'; g.font = '11px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'left'; g.fillText('waiting for the first species to split...', 4, 16); return; }
    var t0 = rows[0].r[3], idx = {};
    for (i = 0; i < rows.length; i++) { if (rows[i].r[3] < t0) t0 = rows[i].r[3]; idx[rows[i].r[0]] = i; }
    var X = function (t) { return 8 + (t - t0) / Math.max(1, t1 - t0) * (w - 52); }, Y = function (i) { return 8 + i * (h - 26) / Math.max(1, rows.length - 1); };
    for (i = 0; i < rows.length; i++) {
      var r = rows[i].r, alive = r[4] === 0, x0 = X(r[3]), x1 = X(alive ? t1 : r[4]), y = Y(i), col = hsl(r[2], 65, alive ? 58 : 40);
      if (rows[i].split && idx[r[1]] !== undefined) { g.strokeStyle = 'rgba(255,255,255,0.25)'; g.lineWidth = 1; g.beginPath(); g.moveTo(x0, Y(idx[r[1]])); g.lineTo(x0, y); g.stroke(); }
      g.strokeStyle = col; g.lineWidth = alive ? 3 : 1.2; g.beginPath(); g.moveTo(x0, y); g.lineTo(Math.max(x0 + 2, x1), y); g.stroke();
      if (!rows[i].split) { g.fillStyle = col; g.beginPath(); g.moveTo(x0, y - 4); g.lineTo(x0 + 4, y); g.lineTo(x0, y + 4); g.lineTo(x0 - 4, y); g.closePath(); g.fill(); }
      if (alive) { g.fillStyle = col; g.font = '600 10px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'left'; g.fillText('#' + r[0], x1 + 4, y + 3.5); }
    }
    g.fillStyle = '#6b6b6b'; g.font = '10px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'left';
    var splits = keep.filter(function (x) { return x.split; }).length;
    g.fillText(splits + ' real splits · ' + (keep.length - splits) + ' arrivals (diamond)' + (hidden ? ' · ' + hidden + ' short-lived arrivals hidden' : ''), 4, h - 2);
  }

  /* ---------- the family tree of the inspected creature ---------- */
  var CAUSE = { 4: 'starved', 5: 'predator', 6: 'eaten', 8: 'old age', 13: 'toxins', 14: 'emigrated' };
  function recRow(r) { return [0, r[0], r[4], r[19], 0, 0, 1000, 0, 50, 100, r[10], r[11], r[12], r[13], r[14], r[15], r[16], r[17], r[18], 0, 0, 0, r[3], 0, r[8], 0, r[20], 0, 0, 0]; }
  function drawPed() {
    var cv = $('ped-cv'); if (!cv) return;
    var w = cv.clientWidth, h = cv.clientHeight; if (cv.width !== Math.round(w * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
    var g = cv.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, w, h);
    if (!ped || !ped.length || ped[0][2][0] !== inspId) { g.fillStyle = '#5f5f5f'; g.font = '11px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'left'; g.fillText('tracing its ancestors...', 4, 16); return; }
    var P = {}, i, n;
    function xy(d, p) { return [(p + 0.5) / Math.pow(2, d) * w, h - 26 - d * (h - 44) / 4]; }
    for (i = 0; i < ped.length; i++) P[ped[i][0] + ':' + ped[i][1]] = ped[i];
    for (i = 0; i < ped.length; i++) {
      n = ped[i]; if (n[0] === 0) continue;
      var a = xy(n[0], n[1]), b = xy(n[0] - 1, n[1] >> 1);
      g.strokeStyle = n[2][21] === 4 ? 'rgba(90,170,255,0.6)' : 'rgba(255,255,255,0.22)'; g.lineWidth = 1; g.beginPath(); g.moveTo(b[0], b[1] - 8); g.lineTo(a[0], a[1] + 8); g.stroke();
    }
    g.imageSmoothingEnabled = false;
    for (i = 0; i < ped.length; i++) {
      n = ped[i]; var r = n[2], q = xy(n[0], n[1]), sp = spriteOf(recRow(r)), sc = n[0] <= 1 ? 2 : n[0] === 2 ? 1.5 : 1, dead = r[7] > 0;
      g.globalAlpha = dead ? 0.45 : 1;
      g.drawImage(sp.cv[0], q[0] - sp.w * sc / 2, q[1] - sp.h * sc / 2, sp.w * sc, sp.h * sc);
      g.globalAlpha = 1;
      if (n[0] <= 2) {
        g.fillStyle = dead ? '#777' : '#ededed'; g.font = (n[0] === 0 ? '600 ' : '') + '10px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'center';
        g.fillText('#' + r[0], q[0], q[1] + 18);
        if (dead) { g.fillStyle = '#8f6060'; g.font = '9px ui-sans-serif,-apple-system,sans-serif'; g.fillText(CAUSE[r[9]] || '', q[0], q[1] + 28); }
        else if (n[0] > 0) { g.fillStyle = '#50e3c2'; g.font = '9px ui-sans-serif,-apple-system,sans-serif'; g.fillText('alive', q[0], q[1] + 28); }
      }
      if (r[21] === 4) { g.fillStyle = '#5aa9ff'; g.font = '9px ui-sans-serif,-apple-system,sans-serif'; g.textAlign = 'center'; g.fillText('migrant', q[0], q[1] - 12); }
    }
    var fam = $('i-fam'); if (fam) { var gens = 0; for (i = 0; i < ped.length; i++) if (ped[i][0] > gens) gens = ped[i][0]; fam.textContent = ped.length + ' ancestors traced, ' + gens + ' generations up'; }
  }

  /* ---------- the inspector ---------- */
  function openInsp(id) {
    var c = rowById(id); if (!c) return;
    inspId = id; net = null; kar = null; ped = null;
    window.swSend('sel', { slot: c[0], isl: view_i });
    $('pg-story').classList.add('off'); $('pg-insp').classList.remove('off');
    setTimeout(resize, 30);
    if (last) inspector(last);
  }
  function closeInsp() { inspId = 0; $('pg-insp').classList.add('off'); $('pg-story').classList.remove('off'); }
  function trait(name, v, lo, hi, col, txt) { return '<div class="tr"><span>' + name + '</span><div class="bar"><i style="width:' + clamp(Math.round((v - lo) / (hi - lo) * 100), 3, 100) + '%;background:' + col + '"></i></div><b>' + txt + '</b></div>'; }
  function inspector(d) {
    var c = rowById(inspId), t = $('i-title'), s = $('i-sub');
    if (!c) { if (s) s.innerHTML = '<span style="color:#ff6b6b">has died</span>'; return; }
    icon($('i-spr'), c);
    if (t) t.textContent = 'Creature #' + c[1];
    var r = role(c);
    if (s) s.innerHTML = 'generation ' + fmtc(c[22]) + ' &middot; species #' + c[2] + ' &middot; <span style="color:' + rgba(ROLE[r], 1) + '">' + r + '</span>';
    var v = $('i-vit');
    if (v) v.innerHTML = '<div>energy<b>' + c[8] + '%</b></div><div>health<b>' + c[9] + '%</b></div><div>age<b>' + Math.round(c[23] / 33) + 's</b></div><div>children / kills<b>' + c[24] + ' / ' + c[25] + '</b></div>';
    var tr = $('i-traits');
    var bc = c[35] || [0, 0, 0, 0, 0];
    if (tr) tr.innerHTML = '<p class="cap" style="margin:0 0 8px"><b>Body:</b> ' + (c[32] || 1) + ' nodes &middot; ' + bc[2] + ' fins, ' + bc[0] + ' spikes, ' + bc[1] + ' armor, ' + bc[3] + ' mouths &middot; ' + bc[4] + ' muscles &middot; mass ' + ((c[31] || 0) / 100).toFixed(1) + '</p>' +
      trait('scale', c[10], 30, 200, '#ffdc78', (c[10] / 100).toFixed(2)) + trait('rhythm', c[11], 30, 250, '#5ac8ff', (c[11] / 100).toFixed(2)) +
      trait('muscle', c[12], 0, 200, '#9aa8bc', (c[12] / 100).toFixed(2)) + trait('spike power', c[34] || 0, 0, 200, '#ff5a5a', String(c[34] || 0)) +
      trait('sight', c[33] || c[14], 5, 80, '#50e3c2', ((c[33] || c[14]) / 100).toFixed(2)) + trait('diet', c[15], 0, 100, '#ff9a50', c[15] < 35 ? 'plants' : c[15] > 65 ? 'meat' : 'both') +
      trait('learning', c[29], 0, 200, '#a78bfa', (c[29] / 1000).toFixed(3)) + trait('brain', c[26], 5, 24, '#5aa9ff', c[26] + ' n');
    var bs = $('i-bsub'); if (bs) bs.textContent = c[26] + ' neurons, ' + c[27] + ' synapses';
    var ip = $('i-par'); if (ip && kar) ip.innerHTML = kar.mom ? (kar.mom === kar.dad ? 'budded from #' + kar.mom : 'child of #' + kar.mom + ' &times; #' + kar.dad) : 'founder or immigrant';
  }

  /* ---------- controls ---------- */
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target.closest('[data-speed],#b-plast,#b-save,#b-load,#b-reset,#b-close,#b-savecr,.spr,[data-isl]') : null;
    if (!t) return;
    if (t.hasAttribute('data-speed')) window.swSend('speed', { k: Number(t.getAttribute('data-speed')) });
    else if (t.id === 'b-plast') window.swSend('plast', {});
    else if (t.id === 'b-save') { window.swSend('save', {}); toast('Saving checkpoint...'); }
    else if (t.id === 'b-load') { window.swSend('load', {}); toast('Loading checkpoint...'); }
    else if (t.id === 'b-reset') { if (confirm('Start a new random world? The last checkpoint stays on disk until the next save.')) { hist = []; window.swSend('reset', {}); } }
    else if (t.id === 'b-close') closeInsp();
    else if (t.id === 'b-savecr') { if (inspId) { window.swSend('savecr', { isl: view_i, id: inspId }); toast('Saved creature #' + inspId + ' to checkpoints/evolve4/creatures/'); } }
    else if (t.hasAttribute('data-isl')) switchIsland(Number(t.getAttribute('data-isl')));
    else if (t.classList.contains('spr')) { var id = Number(t.getAttribute('data-id')); if (id) openInsp(id); }
  });
  function pick(mx, my) {
    if (!last) return null;
    var now = performance.now(), best = null, bd = 0.035 * 0.035;
    for (var i = 0; i < last.cr.length; i++) { var c = last.cr[i], p = pos[c[1]]; if (!p) continue; var q = at(p, now), dx = q[0] - mx, dy = q[1] - my, d2 = dx * dx + dy * dy; if (d2 < bd) { bd = d2; best = c; } }
    return best;
  }
  ac.addEventListener('mousemove', function (e) {
    var r = ac.getBoundingClientRect(); mouse = [e.clientX - r.left, e.clientY - r.top];
    var c = pick((mouse[0] - view.ox) / view.s, (mouse[1] - view.oy) / view.s); hover = c ? c[1] : null;
    var tip = $('tip'); if (!tip) return;
    if (!c) { tip.style.opacity = 0; ac.style.cursor = 'default'; return; }
    ac.style.cursor = 'pointer';
    var rl = role(c);
    tip.innerHTML = '<b>Creature #' + c[1] + '</b> <span class="r">&middot; species #' + c[2] + '</span><br><span style="color:' + rgba(ROLE[rl], 1) + '">' + rl + '</span> <span class="r">&middot; generation ' + fmtc(c[22]) + '</span><br>' +
      '<span class="r">energy</span> ' + c[8] + '% <span class="r">&middot; brain</span> ' + c[26] + ' neurons<br><span class="r">' + c[24] + ' children, ' + c[25] + ' kills &middot; click to inspect</span>';
    tip.style.left = Math.min(AW - 200, mouse[0] + 14) + 'px'; tip.style.top = Math.min(AH - 90, mouse[1] + 14) + 'px'; tip.style.opacity = 1;
  });
  ac.addEventListener('mouseleave', function () { hover = null; mouse = null; var tip = $('tip'); if (tip) tip.style.opacity = 0; });
  ac.addEventListener('mousedown', function () { if (hover) openInsp(hover); });

  /* ---------- draw: the world ---------- */
  function drawSlide(now) {
    var g = wg, d = last, i, f = Math.floor(now / 400) & 1;
    if (bgc) g.drawImage(bgc, 0, 0); else { g.fillStyle = '#080a10'; g.fillRect(0, 0, WP, WP); }
    if (!d) return;
    if (ENV === 4) g.drawImage(caustics()[Math.floor(now / 260) % 4], 0, 0);
    if (ENV === 5) { g.fillStyle = 'rgba(120,200,190,0.05)'; for (var sh = 0; sh < 3; sh++) { var o0 = ((now * 0.006 + sh * 110) % (WP + 160)) - 80; g.beginPath(); g.moveTo(o0, 0); g.lineTo(o0 + 30, 0); g.lineTo(o0 - 50, WP); g.lineTo(o0 - 80, WP); g.closePath(); g.fill(); } }
    if (ENV >= 4) { drawEnvHazards(g, now, f); drawEnvFood(g, d, now, f); return; }
    for (i = 0; i < meadows.length; i++) {
      var mr = meadows[i][2] / 1000 * WP, md = disc(mr, MEAD[view_i % 4], 0.55, 'm' + (view_i % 4) + Math.round(mr));
      g.drawImage(md, Math.round(meadows[i][0] / 1000 * WP - md.width / 2), Math.round(meadows[i][1] / 1000 * WP - md.height / 2));
    }
    for (i = 0; i < vents.length; i++) {
      var vr = vents[i][2] / 1000 * WP, vx = vents[i][0] / 1000 * WP, vy = vents[i][1] / 1000 * WP;
      var vd = disc(vr, 'rgba(150,60,200,0.75)', 0.85, 'v' + Math.round(vr)), vd2 = disc(vr * 0.55, 'rgba(210,120,255,0.8)', 0.7, 'w' + Math.round(vr));
      g.drawImage(vd, Math.round(vx - vd.width / 2), Math.round(vy - vd.height / 2)); g.drawImage(vd2, Math.round(vx - vd2.width / 2), Math.round(vy - vd2.height / 2));
      for (var b = 0; b < 7; b++) {
        var ph = ((now / 1800) + b / 7) % 1, bx = vx + (hash(b, i) - 0.5) * vr * 1.2 + Math.sin(now / 300 + b) * 1.5, by = vy + vr * 0.4 - ph * vr * 1.5;
        g.fillStyle = 'rgba(230,170,255,' + (0.9 - ph * 0.8) + ')'; g.fillRect(Math.round(bx), Math.round(by), 1, 1);
      }
    }
    if (d.poison) for (i = 0; i < d.poison.length; i++) {
      var qx = Math.round(d.poison[i][0] / 1000 * WP), qy = Math.round(d.poison[i][1] / 1000 * WP);
      g.fillStyle = '#5b1f7a'; g.fillRect(qx - 1, qy, 3, 1); g.fillRect(qx, qy - 1, 1, 3);
      g.fillStyle = (f ^ (i & 1)) ? '#d68cff' : '#b45cf0'; g.fillRect(qx, qy, 1, 1); g.fillRect(qx - 1, qy - 1, 1, 1); g.fillRect(qx + 1, qy + 1, 1, 1);
    }
    for (i = 0; i < d.plants.length; i++) {
      var x = Math.round(d.plants[i][0] / 1000 * WP), y = Math.round(d.plants[i][1] / 1000 * WP), h = hash(d.plants[i][0], d.plants[i][1]);
      g.fillStyle = '#1f7a5c'; g.fillRect(x - 1, y, 3, 1); g.fillRect(x, y - 1, 1, 3);
      g.fillStyle = (f ^ (h > 0.5)) ? '#6ff0cf' : '#3cc7a5'; g.fillRect(x, y, 1, 1);
      if (h > 0.6) { g.fillStyle = '#2aa383'; g.fillRect(x + 1, y - 2, 1, 1); }
    }
    for (i = 0; i < d.meat.length; i++) {
      var mx = Math.round(d.meat[i][0] / 1000 * WP), my = Math.round(d.meat[i][1] / 1000 * WP), r = d.meat[i][2] > 30 ? 2 : 1;
      g.fillStyle = '#6b1d24'; g.fillRect(mx - r, my - r + 1, r * 2 + 1, r * 2);
      g.fillStyle = '#c4423f'; g.fillRect(mx - r + 1, my - r, Math.max(1, r * 2 - 1), Math.max(1, r * 2 - 1));
      g.fillStyle = '#ffb3a1'; g.fillRect(mx - r + 1, my - r, 1, 1);
    }
  }
  function drawEnvHazards(g, now, f) {
    var i, j;
    for (i = 0; i < vents.length; i++) {
      var vx = vents[i][0] / 1000 * WP, vy = vents[i][1] / 1000 * WP, vr = vents[i][2] / 1000 * WP;
      if (ENV === 4) {           /* a jellyfish bloom: pulsing translucent bells */
        for (j = 0; j < 6; j++) {
          var a = hash(j, i + 9) * 6.2832 + now / 6000, rr = hash(i, j + 3) * vr * 0.85, jx = Math.round(vx + Math.cos(a) * rr), jy = Math.round(vy + Math.sin(a) * rr), pu = (Math.floor(now / 300) + j) & 1;
          g.fillStyle = 'rgba(255,154,208,0.75)'; g.fillRect(jx - 2 - pu, jy - 2, 5 + pu * 2, 2); g.fillRect(jx - 1, jy - 3, 3, 1);
          g.fillStyle = 'rgba(255,200,230,0.6)'; for (var t = 0; t < 3; t++) g.fillRect(jx - 2 + t * 2, jy + ((t + Math.floor(now / 200)) & 1), 1, 2);
        }
      } else if (ENV === 5) {    /* an urchin barren: spiky purple balls */
        for (j = 0; j < 9; j++) {
          var ux = Math.round(vx + (hash(j, i) - 0.5) * vr * 1.6), uy = Math.round(vy + (hash(i, j) - 0.5) * vr * 1.6);
          g.fillStyle = '#3a1450'; g.fillRect(ux - 1, uy - 1, 3, 3); g.fillStyle = '#7a3fa0';
          g.fillRect(ux - 2, uy, 1, 1); g.fillRect(ux + 2, uy, 1, 1); g.fillRect(ux, uy - 2, 1, 1); g.fillRect(ux, uy + 2, 1, 1); g.fillRect(ux - 2, uy - 2, 1, 1); g.fillRect(ux + 2, uy + 2, 1, 1);
        }
      } else if (ENV === 6) {    /* a brine pool */
        var bd = disc(vr, 'rgba(20,90,90,0.85)', 0.9, 'brine' + Math.round(vr)); g.drawImage(bd, Math.round(vx - bd.width / 2), Math.round(vy - bd.height / 2));
        for (j = 0; j < 20; j++) { var ba = j / 20 * 6.2832; if (((Math.floor(now / 250) + j) % 5) === 0) { g.fillStyle = '#e8ffff'; g.fillRect(Math.round(vx + Math.cos(ba) * vr), Math.round(vy + Math.sin(ba) * vr), 1, 1); } }
      } else if (ENV === 7) {    /* a black smoker: heat glow, chimney, glowing mouth */
        var gd = disc(vr * 1.7, 'rgba(255,90,20,0.22)', 0.75, 'heat' + Math.round(vr)); g.drawImage(gd, Math.round(vx - gd.width / 2), Math.round(vy - gd.height / 2));
        var hd2 = disc(vr, 'rgba(255,140,40,0.35)', 0.8, 'hot' + Math.round(vr)); g.drawImage(hd2, Math.round(vx - hd2.width / 2), Math.round(vy - hd2.height / 2));
        var ch = Math.round(vr * 0.9), cw = Math.max(3, Math.round(vr * 0.28));
        for (var yy = 0; yy < ch; yy++) { var wv = cw + (yy > ch * 0.6 ? 1 : 0); g.fillStyle = (yy & 1) ? '#262022' : '#322a2c'; g.fillRect(Math.round(vx - wv / 2), Math.round(vy - yy), wv, 1); }
        g.fillStyle = (f ? '#ffb040' : '#ff7a20'); g.fillRect(Math.round(vx - cw / 2), Math.round(vy - ch), cw, 1); g.fillStyle = '#fff0b0'; g.fillRect(Math.round(vx), Math.round(vy - ch), 1, 1);
      }
    }
  }
  function drawEnvFood(g, d, now, f) {
    var i;
    for (i = 0; d.poison && i < d.poison.length; i++) {
      var qx = Math.round(d.poison[i][0] / 1000 * WP), qy = Math.round(d.poison[i][1] / 1000 * WP);
      if (ENV === 4) { g.fillStyle = 'rgba(255,154,208,0.8)'; g.fillRect(qx - 1, qy - 1, 3, 1); g.fillRect(qx, qy, 1, 2); }
      else if (ENV === 5) { g.fillStyle = '#7a3fa0'; g.fillRect(qx, qy, 1, 1); g.fillRect(qx - 1, qy, 1, 1); g.fillRect(qx + 1, qy, 1, 1); g.fillRect(qx, qy - 1, 1, 1); g.fillRect(qx, qy + 1, 1, 1); }
      else if (ENV === 6) { g.fillStyle = (f ^ (i & 1)) ? '#2fb0a0' : '#1f8070'; g.fillRect(qx - 1, qy, 2, 2); }
      else { g.fillStyle = (f ^ (i & 1)) ? '#f0dc50' : '#c8b030'; g.fillRect(qx, qy - 1, 1, 2); g.fillRect(qx - 1, qy, 3, 1); }
    }
    for (i = 0; i < d.plants.length; i++) {
      var x = Math.round(d.plants[i][0] / 1000 * WP), y = Math.round(d.plants[i][1] / 1000 * WP), h = hash(d.plants[i][0], d.plants[i][1]);
      if (ENV === 4) { g.fillStyle = (f ^ (h > 0.5)) ? '#e6fbff' : '#9fe8f5'; g.fillRect(x, y, 1, 1); g.fillStyle = 'rgba(190,240,255,0.6)'; g.fillRect(x + 1, y + 1, 1, 1); if (h > 0.5) g.fillRect(x - 1, y + 1, 1, 1); }
      else if (ENV === 5) { g.fillStyle = '#5a7a2a'; g.fillRect(x - 1, y, 3, 2); g.fillStyle = (f ^ (h > 0.5)) ? '#a8e060' : '#8fd14f'; g.fillRect(x, y - 1, 2, 1); }
      else if (ENV === 6) { g.fillStyle = '#ff9a7a'; g.fillRect(x - 1, y, 3, 1); g.fillStyle = '#ffd0b8'; g.fillRect(x + 1 + (f ? 1 : 0), y - 1, 1, 1); }
      else { g.fillStyle = '#e8e0d0'; g.fillRect(x, y - 1, 1, 3); g.fillStyle = (f ^ (h > 0.5)) ? '#ff3a3a' : '#c81e28'; g.fillRect(x - 1, y - 2, 3, 1); }
    }
    for (i = 0; i < d.meat.length; i++) {
      var mx = Math.round(d.meat[i][0] / 1000 * WP), my = Math.round(d.meat[i][1] / 1000 * WP);
      g.fillStyle = '#6b1d24'; g.fillRect(mx - 1, my, 3, 2); g.fillStyle = '#c4423f'; g.fillRect(mx, my - 1, 1, 2);
    }
  }

  /* ---------- physical bodies: membranes between nodes, then each node drawn by its type ---------- */
  var nspr = {};
  function nodeSprite(type, hue, R) {
    var key = type + ':' + Math.round(hue / 10) + ':' + R;
    if (nspr[key]) return nspr[key];
    var D = R * 2 + 2, cv = document.createElement('canvas'); cv.width = D; cv.height = D;
    var g = cv.getContext('2d'), c0 = D / 2;
    for (var y = 0; y < D; y++) for (var x = 0; x < D; x++) {
      var dx = x + 0.5 - c0, dy = y + 0.5 - c0, d = Math.sqrt(dx * dx + dy * dy);
      if (d > R) continue;
      var edge = d > R - 1.1, light = (-dx - dy) / (R * 1.4), col;
      if (type === 6 || type === 0) {
        var l = type === 6 ? 48 : 58; col = edge ? hsl(hue, 70, 20) : hsl(hue, 60, l + light * 16);
        if (type === 6 && d < Math.max(1, R * 0.35)) col = hsl(hue + 180, 35, 22);
      } else if (type === 2) {
        var seg = Math.floor((Math.atan2(dy, dx) + 3.1416) / 0.8) % 2;
        col = edge ? '#4a5262' : (seg ? '#b9c4d4' : '#8c98ab');
      } else if (type === 4) {
        col = edge ? (((x + y) & 1) ? '#f4f0e8' : '#3a0a10') : (d < R * 0.5 ? '#14040a' : '#7a1822');
      } else if (type === 5) {
        col = d < Math.max(1, R * 0.45) ? '#05060a' : (edge ? '#9aa4b8' : '#f2f6ff');
      } else { col = hsl(hue, 60, 55); }
      g.fillStyle = col; g.fillRect(x, y, 1, 1);
    }
    return (nspr[key] = cv);
  }
  function pixelLine(a, b, w, col) {
    var dx = b[0] - a[0], dy = b[1] - a[1], d = Math.sqrt(dx * dx + dy * dy), st = Math.max(1, Math.ceil(d / Math.max(1, w * 0.6)));
    ag.fillStyle = col;
    for (var i = 0; i <= st; i++) { var u = i / st; ag.fillRect(a[0] + dx * u - w / 2, a[1] + dy * u - w / 2, w, w); }
  }
  /* returns the body's screen radius */
  function drawMesh(c, B, now) {
    var bd = c[30] || [], n = B.length, hue = c[3], P = [], R = 4, i;
    if (!n) return R;
    for (i = 0; i < n; i++) P.push([SX(B[i][0]), SY(B[i][1])]);
    var rp = function (i) { return bd[i * 5 + 1] / 10000 / WS * view.s; };
    ag.fillStyle = hsl(hue, 60, 50, 0.16);
    for (i = 0; i < n; i++) { if (bd[i * 5] === 1) continue; ag.beginPath(); ag.arc(P[i][0], P[i][1], Math.max(view.k, rp(i)) * 1.9, 0, 6.2832); ag.fill(); }
    for (i = 1; i < n; i++) {
      var pi = bd[i * 5 + 2]; if (pi < 0 || pi >= n) continue;
      var tw = Math.max(view.k * 1.2, Math.min(rp(pi), rp(i)) * 1.5);
      pixelLine(P[pi], P[i], tw, hsl(hue, 45, 26, 0.95));
      pixelLine(P[pi], P[i], Math.max(view.k * 0.6, tw * 0.5), hsl(hue, 55, 44, 0.95));
    }
    var order = [3, 0, 2, 4, 5, 6, 1];
    ag.imageSmoothingEnabled = false;
    for (var oi = 0; oi < order.length; oi++) {
      var T = order[oi];
      for (i = 0; i < n; i++) {
        if (bd[i * 5] !== T) continue;
        var x = P[i][0], y = P[i][1], r = Math.max(view.k * 0.8, rp(i)), pi2 = bd[i * 5 + 2], ux = 0, uy = 0;
        if (i > 0 && pi2 >= 0 && pi2 < n) { var lx = x - P[pi2][0], ly = y - P[pi2][1], ll = Math.sqrt(lx * lx + ly * ly) || 1; ux = lx / ll; uy = ly / ll; }
        var dd = Math.sqrt((x - P[0][0]) * (x - P[0][0]) + (y - P[0][1]) * (y - P[0][1])) + r; if (dd > R) R = dd;
        if (T === 3) {           /* fin: a translucent paddle along its link */
          ag.save(); ag.translate(x, y); ag.rotate(Math.atan2(uy, ux));
          ag.fillStyle = hsl(hue + 40, 75, 66, 0.55); ag.beginPath(); ag.ellipse(0, 0, r * 1.9, r * 0.8, 0, 0, 6.2832); ag.fill();
          ag.strokeStyle = hsl(hue + 40, 80, 80, 0.8); ag.lineWidth = 1; ag.stroke(); ag.restore();
        } else if (T === 1) {    /* spike: a red blade pointing outward */
          var tipx = x + ux * r * 2.4, tipy = y + uy * r * 2.4, nx = -uy * r * 0.85, ny = ux * r * 0.85;
          ag.fillStyle = '#c8323a'; ag.beginPath(); ag.moveTo(x + nx, y + ny); ag.lineTo(tipx, tipy); ag.lineTo(x - nx, y - ny); ag.closePath(); ag.fill();
          ag.fillStyle = '#ffd8d0'; ag.fillRect(tipx - view.k * 0.4, tipy - view.k * 0.4, view.k * 0.8, view.k * 0.8);
        } else {
          var Rs = Math.max(1, Math.round(r / view.k * 2)), sp = nodeSprite(T, hue, Rs), sz = sp.width * view.k / 2;
          ag.drawImage(sp, x - sz / 2, y - sz / 2, sz, sz);
        }
      }
    }
    return R;
  }

  function SX(u) { return view.ox + u * view.s; }
  function SY(u) { return view.oy + u * view.s; }
  function drawArena(now) {
    ag.clearRect(0, 0, AW, AH);
    drawSlide(now);
    ag.imageSmoothingEnabled = false;
    ag.drawImage(wc, view.ox, view.oy, view.s, view.s);
    ag.strokeStyle = 'rgba(255,255,255,0.10)'; ag.lineWidth = 1; ag.strokeRect(view.ox - 0.5, view.oy - 0.5, view.s + 1, view.s + 1);
    if (!last) return;
    ag.font = '600 10px ui-sans-serif,-apple-system,sans-serif'; ag.textAlign = 'center';
    var VL = ['TOXIC VENT', 'TOXIC VENT', 'TOXIC VENT', 'TOXIC VENT', 'JELLYFISH BLOOM', 'URCHIN BARREN', 'BRINE POOL', 'BLACK SMOKER'], VC = ['rgba(214,140,255,0.75)', 'rgba(214,140,255,0.75)', 'rgba(214,140,255,0.75)', 'rgba(214,140,255,0.75)', 'rgba(255,170,215,0.8)', 'rgba(190,140,230,0.75)', 'rgba(140,230,220,0.8)', 'rgba(255,170,90,0.85)'];
    var ev = ENV < 0 ? 0 : ENV;
    for (i = 0; i < vents.length; i++) { ag.fillStyle = VC[ev]; ag.fillText(VL[ev], SX(vents[i][0] / 1000), SY(vents[i][1] / 1000) + vents[i][2] / 1000 * view.s + 12); }
    if (ENV < 4) for (i = 0; i < meadows.length; i++) { ag.fillStyle = 'rgba(110,230,170,0.35)'; ag.fillText('algae meadow', SX(meadows[i][0] / 1000), SY(meadows[i][1] / 1000) - meadows[i][2] / 1000 * view.s - 4); }
    if (ENV === 5) for (i = 0; i < kelpZ.length; i++) { ag.fillStyle = 'rgba(160,230,120,0.45)'; ag.fillText('KELP BED', SX(kelpZ[i][0] / 1000), SY(kelpZ[i][1] / 1000) + kelpZ[i][2] / 1000 * view.s * 0.5 + 16); }
    ag.fillStyle = 'rgba(190,200,215,0.45)'; if (ENV === 0) ag.fillText('ROCK REEF', SX(1.28 / WS), SY(1.03 / WS)); if (ENV === 2) ag.fillText('BOULDER MAZE', SX(0.5), SY(0.5) + 34);
    var k = view.k, i;
    for (i = 0; i < last.preds.length && i < predPos.length; i++) {
      var pr = last.preds[i], q = predPos[i], u = clamp((now - q.t) / gap, 0, 1), x = SX(q.x0 + (q.x1 - q.x0) * u), y = SY(q.y0 + (q.y1 - q.y0) * u), mode = pr[2];
      if (mode === 3) {
        var rr = (10 + 24 * clamp(pr[3] / 55, 0, 1)) * k;
        ag.strokeStyle = 'rgba(255,176,46,' + (0.45 + 0.4 * Math.sin(now / 90)) + ')'; ag.lineWidth = 2; ag.setLineDash([6, 5]); ag.beginPath(); ag.arc(x, y, rr, 0, 6.2832); ag.stroke(); ag.setLineDash([]);
        ag.fillStyle = '#ffd36b'; ag.font = '700 12px ui-sans-serif,-apple-system,sans-serif'; ag.textAlign = 'center'; ag.fillText('stalking', x, y - 13 * k);
      }
      if (mode === 1) { var gl = ag.createRadialGradient(x, y, 0, x, y, 16 * k); gl.addColorStop(0, 'rgba(255,60,60,0.35)'); gl.addColorStop(1, 'rgba(255,60,60,0)'); ag.fillStyle = gl; ag.fillRect(x - 16 * k, y - 16 * k, 32 * k, 32 * k); }
      ag.save(); ag.translate(x, y); ag.scale(k, k); ag.globalAlpha = mode === 2 ? 0.55 : 1;
      ag.drawImage(predSpr[Math.floor(now / (mode === 1 ? 120 : 400)) & 1], -10.5, -10.5); ag.restore();
      if (mode === 2) { ag.fillStyle = 'rgba(200,200,230,0.6)'; ag.font = '600 11px ui-sans-serif,-apple-system,sans-serif'; ag.textAlign = 'center'; ag.fillText('resting', x, y + 15 * k); }
    }
    var sel = null, hov = null;
    for (i = 0; i < last.cr.length; i++) {
      var c = last.cr[i], p = pos[c[1]]; if (!p) continue;
      var a = at(p, now), cx = SX(a[0]), cy = SY(a[1]), sig = c[19] / 100;
      ag.globalAlpha = clamp((now - p.born) / 400, 0, 1);
      var R = drawMesh(c, atBody(p, now), now), s = { h: Math.max(6, R * 2) / k };
      ag.globalAlpha = 1;
      if (Math.abs(sig) > 0.5) {
        var gr2 = ag.createRadialGradient(cx, cy, 0, cx, cy, R * 1.6); gr2.addColorStop(0, sig > 0 ? 'rgba(80,227,255,0.25)' : 'rgba(255,80,220,0.25)'); gr2.addColorStop(1, 'rgba(0,0,0,0)');
        ag.fillStyle = gr2; ag.fillRect(cx - R * 1.6, cy - R * 1.6, R * 3.2, R * 3.2);
      }
      if (c[28] > 0) { ag.strokeStyle = 'rgba(255,70,70,' + (c[28] / 10) + ')'; ag.lineWidth = 2; ag.beginPath(); ag.arc(cx, cy, R + 2, 0, 6.2832); ag.stroke(); }
      if (c[1] === inspId) sel = [cx, cy, s, c];
      if (c[1] === hover) hov = [cx, cy, s, c];
    }
    if (ENV >= 5) { drawFront(now); ag.imageSmoothingEnabled = false; ag.drawImage(oc, view.ox, view.oy, view.s, view.s); }
    if (hov && (!sel || hov[3][1] !== sel[3][1])) { ag.strokeStyle = 'rgba(255,255,255,0.55)'; ag.lineWidth = 1.2; ag.beginPath(); ag.arc(hov[0], hov[1], hov[2].h * k * 0.62, 0, 6.2832); ag.stroke(); }
    if (sel) {
      var R = sel[2].h * k * 0.62 + 2 + Math.sin(now / 250) * 1.5;
      ag.strokeStyle = '#fff'; ag.lineWidth = 1.5; ag.beginPath(); ag.arc(sel[0], sel[1], R, 0, 6.2832); ag.stroke();
      ag.strokeStyle = 'rgba(255,255,255,0.18)'; ag.setLineDash([3, 5]); ag.beginPath(); ag.arc(sel[0], sel[1], sel[3][14] / 100 / WS * view.s, 0, 6.2832); ag.stroke(); ag.setLineDash([]);
      ag.fillStyle = '#fff'; ag.font = '600 11px ui-sans-serif,-apple-system,sans-serif'; ag.textAlign = 'center'; ag.fillText('#' + sel[3][1], sel[0], sel[1] - R - 6);
    }
  }

  /* ---------- draw: the inspected brain ---------- */
  function drawBrain(now) {
    var BW = bc.clientWidth, BH = bc.clientHeight; bg.clearRect(0, 0, BW, BH);
    if (!inspId || !last) return;
    var sr = rowOf(last.sel); if (!sr || sr[1] !== inspId || !last.acts.length) { bg.fillStyle = '#666'; bg.font = '12px ui-sans-serif,-apple-system,sans-serif'; bg.textAlign = 'left'; bg.fillText('reading its brain...', 12, 20); return; }
    var acts = last.acts, sens = last.sens, n = acts.length, i, k, types = net && net.types ? net.types : [];
    function sp(i) { return [78, 8 + (BH - 16) * (i + 0.5) / SENS.length]; }
    function op(i) { return [BW - 64, BH * (0.14 + i * 0.18)]; }
    function hp(i) { var hx = 0.5 + (hash(i, 7) - 0.5) * 0.4, hy = 0.08 + 0.84 * ((i - 5 + 0.5) / Math.max(1, n - 5)); return [100 + (BW - 190) * hx, 10 + (BH - 20) * hy]; }
    var P = []; for (i = 0; i < n; i++) P.push(i < 5 ? op(i) : hp(i));
    if (net && net.e) {
      for (k = 0; k < net.e.length; k++) {
        var e = net.e[k], src = e[0], dst = e[1]; if (dst >= n) continue;
        var a = src >= 1000 ? sp(src - 1000) : P[src], b = P[dst]; if (!a || !b) continue;
        var w = e[4] / 100, w0 = e[3] / 100, learned = Math.abs(w - w0) > 0.15, mod = e[2] === 1;
        var pre = src >= 1000 ? (sens[src - 1000] || 0) / 100 : (acts[src] || 0) / 100;
        var col = mod ? [245, 166, 35] : w >= 0 ? [90, 170, 255] : [255, 90, 90];
        bg.strokeStyle = rgba(col, 0.10 + Math.min(0.45, Math.abs(w) * 0.12) + Math.min(0.35, Math.abs(pre * w) * 0.15));
        bg.lineWidth = 0.6 + Math.min(2.4, Math.abs(w) * 0.6);
        if (mod) bg.setLineDash([3, 3]);
        var mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2 - 16 * (src === dst ? 2 : 1);
        bg.beginPath(); bg.moveTo(a[0], a[1]); bg.quadraticCurveTo(mx, my, b[0], b[1]); bg.stroke(); bg.setLineDash([]);
        if (learned) { bg.strokeStyle = 'rgba(167,139,250,0.6)'; bg.lineWidth = 0.9; bg.beginPath(); bg.moveTo(a[0], a[1]); bg.quadraticCurveTo(mx, my + 3, b[0], b[1]); bg.stroke(); }
        if (Math.abs(pre) > 0.25) {
          var t = ((now / 700) + k * 0.37) % 1, qx = (1 - t) * (1 - t) * a[0] + 2 * (1 - t) * t * mx + t * t * b[0], qy = (1 - t) * (1 - t) * a[1] + 2 * (1 - t) * t * my + t * t * b[1];
          bg.fillStyle = rgba(col, 0.95); bg.beginPath(); bg.arc(qx, qy, 1.6, 0, 6.2832); bg.fill();
        }
      }
    }
    bg.font = '10px ui-sans-serif,-apple-system,sans-serif'; bg.textAlign = 'right';
    for (i = 0; i < SENS.length; i++) {
      var s = sp(i), v = (sens[i] || 0) / 100, av = Math.min(1, Math.abs(v));
      bg.fillStyle = rgba(v >= 0 ? [80, 227, 194] : [255, 120, 120], 0.15 + av * 0.85); bg.fillRect(s[0] - 3, s[1] - 3, 6, 6);
      bg.fillStyle = av > 0.05 ? '#d0d0d0' : '#5a5a5a'; bg.fillText(SENS[i], s[0] - 8, s[1] + 3.5);
    }
    for (i = 0; i < n; i++) {
      var q = P[i], ty = types[i] || 0, v2 = (acts[i] || 0) / 100, av2 = Math.min(1, Math.abs(v2)), c = TCOL[ty] || TCOL[0], r = i < 5 ? 8 : 5;
      var gl = bg.createRadialGradient(q[0], q[1], 0, q[0], q[1], r * 3); gl.addColorStop(0, rgba(c, 0.1 + av2 * 0.5)); gl.addColorStop(1, rgba(c, 0));
      bg.fillStyle = gl; bg.fillRect(q[0] - r * 3, q[1] - r * 3, r * 6, r * 6);
      bg.fillStyle = rgba(c, 0.3 + av2 * 0.7);
      if (ty === 2) { bg.beginPath(); bg.moveTo(q[0], q[1] - r); bg.lineTo(q[0] + r, q[1]); bg.lineTo(q[0], q[1] + r); bg.lineTo(q[0] - r, q[1]); bg.closePath(); bg.fill(); }
      else if (ty === 1) bg.fillRect(q[0] - r * 0.85, q[1] - r * 0.85, r * 1.7, r * 1.7);
      else { bg.beginPath(); bg.arc(q[0], q[1], r, 0, 6.2832); bg.fill(); }
      if (i < 5) { bg.textAlign = 'left'; bg.fillStyle = '#ededed'; bg.font = '500 11px ui-sans-serif,-apple-system,sans-serif'; bg.fillText(OUTS[i], q[0] + 13, q[1] + 1); bg.font = '10px ui-sans-serif,-apple-system,sans-serif'; bg.fillStyle = '#777'; bg.fillText((v2 >= 0 ? '+' : '') + v2.toFixed(2), q[0] + 13, q[1] + 13); }
    }
  }

  /* ---------- draw: its two chromosomes ---------- */
  function roundRect(g, x, y, w, h, r) { g.beginPath(); g.moveTo(x + r, y); g.lineTo(x + w - r, y); g.quadraticCurveTo(x + w, y, x + w, y + r); g.lineTo(x + w, y + h - r); g.quadraticCurveTo(x + w, y + h, x + w - r, y + h); g.lineTo(x + r, y + h); g.quadraticCurveTo(x, y + h, x, y + h - r); g.lineTo(x, y + r); g.quadraticCurveTo(x, y, x + r, y); g.closePath(); }
  function drawGenome(now) {
    var GW = gc.clientWidth, GH = gc.clientHeight; gg.clearRect(0, 0, GW, GH);
    if (!inspId || !kar || !last) return;
    var sr = rowOf(last.sel); if (!sr || sr[1] !== inspId) return;
    var L = 22, R = GW - 4, top = 18, bw = (R - L) / 19, ch = 30, i;
    var rows = [['A', kar.a, kar.an], ['B', kar.b, kar.bn]];
    for (var r = 0; r < 2; r++) {
      var y0 = top + r * (ch + 26), al = rows[r][1];
      gg.fillStyle = '#8f8f8f'; gg.font = '600 11px ui-sans-serif,-apple-system,sans-serif'; gg.textAlign = 'left'; gg.fillText(rows[r][0], 4, y0 + ch / 2 + 4);
      gg.fillStyle = '#121418'; roundRect(gg, L, y0, R - L, ch, 12); gg.fill();
      for (i = 0; i < 19 && i < al.length; i++) {
        var v = al[i][0] / 100, dom = al[i][1] / 100, c = GROUPS[LGROUP[i]].c, x = L + i * bw, other = rows[1 - r][1][i], het = other && Math.abs(other[0] - al[i][0]) > 12;
        gg.fillStyle = rgba(c, 0.15 + 0.8 * v); gg.fillRect(x + 1.5, y0 + 3, bw - 3, ch - 6);
        gg.fillStyle = 'rgba(255,255,255,' + (0.2 + dom * 0.6) + ')'; gg.fillRect(x + 1.5, y0 + 3, bw - 3, Math.max(1.5, (ch - 6) * 0.25 * dom));
        if (het) { gg.fillStyle = 'rgba(255,255,255,' + (0.5 + 0.4 * Math.sin(now / 300 + i)) + ')'; gg.fillRect(x + bw / 2 - 1, y0 + ch + 2, 2, 3); }
      }
      gg.fillStyle = '#6b6b6b'; gg.font = '10px ui-sans-serif,-apple-system,sans-serif'; gg.textAlign = 'right';
      gg.fillText('brain genes on this copy: ' + rows[r][2][0] + ' neurons, ' + rows[r][2][1] + ' synapses', R, y0 - 4);
    }
    var ly = top + 2 * (ch + 26) + 4;
    gg.font = '9.5px ui-sans-serif,-apple-system,sans-serif'; gg.textAlign = 'right';
    for (i = 0; i < 19; i++) { gg.save(); gg.translate(L + i * bw + bw / 2 + 3, ly); gg.rotate(-1.0); gg.fillStyle = rgba(GROUPS[LGROUP[i]].c, 0.85); gg.fillText(LOCI[i], 0, 0); gg.restore(); }
  }

  function frame(now) {
    requestAnimationFrame(frame);
    if (!AW) { resize(); return; }
    drawArena(now);
    if (inspId) { drawBrain(now); drawGenome(now); drawPed(); }
  }
  /* tell the server which island this page watches (several viewers can watch different islands) */
  setInterval(function () { if (window.swSend) window.swSend('view', { i: view_i }); }, 2000);
  setTimeout(function () { if (window.swSend) window.swSend('view', { i: view_i, fresh: 1 }); }, 300);
  window.__swEvolve3 = { get last() { return last; }, sprite: spriteOf };
  resize();
  requestAnimationFrame(frame);
})();
