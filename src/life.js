/* Life at Scale - client. Source of truth for src/LifeJs.sw
   (python3 scripts/embed_js.py src/life.js LifeJs src/LifeJs.sw).

   One frame per ~33ms+ from the server:
     w   board side            gen  generation number
     b   cells packed 30 per int (MSB first), row-major
     pop live cells            procs processes alive in the node
     gps generations/s         mps cell messages/s (10 per cell per generation)
     spms ms to spawn the board's processes
     restarts crashes          from swarm_stats()
     paused delay              controls echoed back
     k   [cell idx] killed since last frame     r  [cell idx] respawned
   Every square is a real swarmrt process. Nothing is simulated. */
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var cv = $('life-cv'), box = $('board');
  if (!cv) return;
  var g = cv.getContext('2d');
  var dpr = Math.min(2, window.devicePixelRatio || 1);
  var off = document.createElement('canvas'), og = off.getContext('2d');
  var W = 0, N = 0, cs = 1, bw = 0, bh = 0, img = null;
  var cells = new Uint8Array(0), age = new Uint16Array(0), trail = new Float32Array(0);
  var rings = [], shake = 0, last = null, framesN = 0, fps = 0, fpsT = performance.now(), dirty = true;
  /* ?slow=6 plays the kill / respawn effects 6x slower (the simulation is unchanged) */
  var SLOW = Number((location.search.match(/slow=([0-9.]+)/) || [0, 1])[1]) || 1;
  var stats = {}, painting = false, paintVal = 1, pending = {}, paintT = 0, hoverIdx = -1;

  function fmt(n) { n = Math.round(n || 0); if (n >= 1e9) return (n / 1e9).toFixed(2) + 'B'; if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k'; return String(n); }
  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }

  /* ---------- sizing ---------- */
  function resize() {
    bw = box.clientWidth; bh = box.clientHeight;
    if (!W) return;
    cs = Math.max(1, Math.min((bw - 40) / W, (bh - 40) / W));
    if (cs >= 3) cs = Math.floor(cs * 2) / 2;
    var px = Math.floor(W * cs);
    cv.style.width = px + 'px'; cv.style.height = px + 'px';
    cv.width = px * dpr; cv.height = px * dpr;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    dirty = true;
  }
  if (window.ResizeObserver) new ResizeObserver(resize).observe(box); else window.addEventListener('resize', resize);

  function setBoard(w) {
    W = w; N = w * w;
    cells = new Uint8Array(N); age = new Uint16Array(N); trail = new Float32Array(N);
    off.width = w; off.height = w; img = og.createImageData(w, w);
    rings = []; resize();
  }

  /* ---------- frames ---------- */
  window.SwEvents = window.SwEvents || {};
  window.SwEvents.frame = function (d) {
    var now = performance.now(), i, k, v, base;
    if (d.w !== W) setBoard(d.w);
    for (i = 0; i < d.b.length; i++) {
      v = d.b[i]; base = i * 30;
      for (k = 0; k < 30; k++) {
        var idx = base + k; if (idx >= N) break;
        var s = (v >> (29 - k)) & 1;
        if (s) { age[idx] = age[idx] < 65000 ? age[idx] + 1 : age[idx]; trail[idx] = 1; } else { age[idx] = 0; }
        cells[idx] = s;
      }
    }
    last = d; framesN++; dirty = true;
    stat('procs', d.procs, fmtc, 'spawned in ' + fmtc(d.spms) + ' ms', 'up');
    stat('gps', d.gps, function (x) { return x.toFixed(x < 10 ? 1 : 0); }, 'generation ' + fmtc(d.gen), '');
    stat('mps', d.mps, fmt, '10 messages per cell per generation', '');
    stat('pop', d.pop, fmtc, (d.pop / N * 100).toFixed(1) + '% of the board alive', '');
    stat('heal', d.restarts, fmtc, d.crashes ? fmtc(d.crashes) + ' crashes so far' : 'nothing has crashed yet', d.crashes ? 'bad' : '');
    var hs = $('h-sleep'); if (hs) hs.innerHTML = d.sl ? '<b>' + fmtc(d.sl) + '</b> idle processes parked (last batch: ' + fmtc(d.sll) + ' spawned in <b>' + fmtc(d.slms) + ' ms</b>). The board is still running.' : 'Parked processes cost ~10-20 KB each. The board keeps running while you stack tens of thousands of them next to it. The runtime ceiling is 100,000.';
    var bh2 = $('bh'); if (bh2) bh2.innerHTML = '<b>' + W + ' &times; ' + W + '</b> &middot; ' + fmtc(N) + ' processes &middot; generation ' + fmtc(d.gen) + (d.paused ? ' &middot; paused' : '');
    var sz = document.querySelectorAll('[data-size]'), sp = document.querySelectorAll('[data-speed]');
    for (i = 0; i < sz.length; i++) sz[i].classList.toggle('on', Number(sz[i].getAttribute('data-size')) === W);
    for (i = 0; i < sp.length; i++) sp[i].classList.toggle('on', Number(sp[i].getAttribute('data-speed')) === d.delay);
    var pb = $('b-pause'); if (pb) pb.textContent = d.paused ? 'Resume' : 'Pause';
  };

  /* kills and respawns are announced the moment they happen, not with the next generation */
  window.SwEvents.kills = function (d) {
    var now = performance.now();
    for (var i = 0; i < d.k.length; i++) { var a = d.k[i]; cells[a] = 0; age[a] = 0; trail[a] = 0; if (rings.length < 900) rings.push({ i: a, t: now, c: '255,77,77', big: d.n < 150 }); }
    if (d.n > 40) shake = Math.min(14, d.n / 80 + 4);
    dirty = true;
  };
  window.SwEvents.revived = function (d) {
    var now = performance.now();
    for (var i = 0; i < d.r.length; i++) if (rings.length < 900) rings.push({ i: d.r[i], t: now, c: '80,227,194', big: d.n < 150 });
    dirty = true;
  };

  /* ---------- animated counters ---------- */
  function stat(id, v, f, sub, tone) {
    var s = stats[id] || (stats[id] = { cur: v, tgt: v, shown: '' });
    s.tgt = v; s.fmt = f;
    var d = $('d-' + id); if (d) { d.textContent = sub; d.className = 'chip ' + (tone || ''); }
  }
  function tickStats() {
    for (var id in stats) {
      var s = stats[id]; s.cur += (s.tgt - s.cur) * 0.22; if (Math.abs(s.tgt - s.cur) < 0.5) s.cur = s.tgt;
      var t = s.fmt(s.cur), el = $('v-' + id);
      if (el && t !== s.shown) { el.textContent = t; s.shown = t; }
    }
  }

  /* ---------- drawing ---------- */
  function paintImage() {
    var data = img.data, i, p;
    for (i = 0; i < N; i++) {
      p = i * 4;
      if (cells[i]) {
        var a = age[i], r, gg, b;
        if (a < 3) { r = 255; gg = 255; b = 255; }
        else if (a < 14) { var t = (a - 3) / 11; r = 255 - t * 175; gg = 255 - t * 45; b = 255; }
        else if (a < 90) { var t2 = (a - 14) / 76; r = 80 + t2 * 80; gg = 210 - t2 * 120; b = 255; }
        else { r = 150; gg = 90; b = 240; }
        data[p] = r; data[p + 1] = gg; data[p + 2] = b; data[p + 3] = 255;
      } else {
        var tr = trail[i];
        if (tr > 0.02) { trail[i] = tr * 0.9; data[p] = 8 + tr * 30; data[p + 1] = 10 + tr * 70; data[p + 2] = 18 + tr * 120; }
        else { trail[i] = 0; data[p] = 6; data[p + 1] = 7; data[p + 2] = 11; }
        data[p + 3] = 255;
      }
    }
    og.putImageData(img, 0, 0);
  }

  function draw(now) {
    requestAnimationFrame(draw);
    if (now - fpsT > 1000) { fps = framesN; framesN = 0; fpsT = now; var f = $('o-fps'); if (f) f.textContent = fps; }
    tickStats();
    if (!W || !img) return;
    var anyTrail = dirty || rings.length || shake > 0.2;
    if (!anyTrail) return;
    paintImage(); dirty = false;
    var px = W * cs;
    g.save();
    if (shake > 0.2) { g.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake); shake *= 0.9; } else shake = 0;
    g.imageSmoothingEnabled = cs < 2;
    g.clearRect(-20, -20, px + 40, px + 40);
    g.drawImage(off, 0, 0, px, px);
    for (var i = rings.length - 1; i >= 0; i--) {
      var r = rings[i], t = (now - r.t) / (700 * SLOW);
      if (t >= 1) { rings.splice(i, 1); continue; }
      var cx = ((r.i % W) + 0.5) * cs, cy = (Math.floor(r.i / W) + 0.5) * cs;
      g.strokeStyle = 'rgba(' + r.c + ',' + (1 - t) + ')'; g.lineWidth = Math.max(1, cs * 0.35) * (1 - t) + 0.5;
      g.beginPath(); g.arc(cx, cy, Math.max(0.5, cs * 0.6 + (r.big ? cs * 5 + 8 : cs * 1.6 + 3) * t), 0, 6.2832); g.stroke();
    }
    if (hoverIdx >= 0) {
      g.strokeStyle = 'rgba(255,255,255,0.8)'; g.lineWidth = 1;
      g.strokeRect((hoverIdx % W) * cs - 1, Math.floor(hoverIdx / W) * cs - 1, cs + 2, cs + 2);
    }
    g.restore();
  }

  /* ---------- input: draw on the board ---------- */
  function cellAt(e) {
    var r = cv.getBoundingClientRect(), x = Math.floor((e.clientX - r.left) / cs), y = Math.floor((e.clientY - r.top) / cs);
    return (x < 0 || y < 0 || x >= W || y >= W) ? -1 : y * W + x;
  }
  function flush() {
    var ids = Object.keys(pending); if (!ids.length) return;
    window.swSend('paint', { c: ids.join(','), v: paintVal }); pending = {};
  }
  function addPaint(e) {
    var i = cellAt(e); hoverIdx = i; if (i < 0) return;
    if (!pending[i]) { pending[i] = 1; cells[i] = paintVal; if (paintVal) { age[i] = 0; trail[i] = 1; } dirty = true; }
    var now = performance.now(); if (now - paintT > 40) { paintT = now; flush(); }
  }
  cv.addEventListener('pointerdown', function (e) { painting = true; paintVal = e.shiftKey ? 0 : 1; try { cv.setPointerCapture(e.pointerId); } catch (x) {} addPaint(e); });
  cv.addEventListener('pointermove', function (e) { if (painting) addPaint(e); else { hoverIdx = cellAt(e); dirty = true; } });
  cv.addEventListener('pointerup', function () { painting = false; flush(); });
  cv.addEventListener('pointerleave', function () { hoverIdx = -1; dirty = true; });

  /* ---------- controls ---------- */
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target.closest('[data-size],[data-pat],[data-speed],[data-chaos],[data-sleepers],#b-pause,#b-release') : null;
    if (!t) return;
    if (t.hasAttribute('data-size')) { var w = Number(t.getAttribute('data-size')); var bh = $('bh'); if (bh) bh.innerHTML = 'spawning <b>' + fmtc(w * w) + '</b> processes...'; window.swSend('size', { w: w }); }
    else if (t.hasAttribute('data-pat')) window.swSend('pattern', { name: t.getAttribute('data-pat') });
    else if (t.hasAttribute('data-speed')) window.swSend('speed', { ms: Number(t.getAttribute('data-speed')) });
    else if (t.hasAttribute('data-chaos')) { shake = Math.max(shake, 8); window.swSend('chaos', { p: Number(t.getAttribute('data-chaos')) }); }
    else if (t.hasAttribute('data-sleepers')) window.swSend('sleepers', { n: Number(t.getAttribute('data-sleepers')) });
    else if (t.id === 'b-release') window.swSend('release', {});
    else if (t.id === 'b-pause') window.swSend('pause', {});
  });
  window.__swLife = { get cells() { return cells; }, get W() { return W; } };
  requestAnimationFrame(draw);
})();
