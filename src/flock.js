/* Flock - canvas renderer. Source of truth for src/FlockJs.sw
   (python3 scripts/embed_js.py src/flock.js FlockJs src/FlockJs.sw).

   One frame ~every 33ms from the server:
     p  flat [x0,y0,x1,y1,...] boid positions in world units (1600 x 900)
     q  [[x,y,kind,hue],...] live predators (kind 0 repel, 1 attract, 2 blast)
     o  flock order (alignment) x1000     s  avg speed x100     m  mode
   Every boid on screen is a real swarmrt process. */
(function () {
  var WW = 1600, WH = 900;
  var cv = document.getElementById('sky');
  if (!cv) return;
  var g = cv.getContext('2d');
  var dpr = Math.min(2, window.devicePixelRatio || 1);
  var W = 0, H = 0, sc = 1, ox = 0, oy = 0;
  var prev = null, cur = null, curT = 0, interval = 33, nB = 0;
  var preds = [], rings = [], frames = 0, fpsT = performance.now();
  var me = { x: -1, y: -1, down: false, sent: 0 };

  function layout() {
    W = cv.clientWidth; H = cv.clientHeight;
    cv.width = W * dpr; cv.height = H * dpr;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    sc = Math.max(W / WW, H / WH);
    ox = (W - WW * sc) / 2; oy = (H - WH * sc) / 2;
    g.fillStyle = '#06070a'; g.fillRect(0, 0, W, H);
  }
  window.addEventListener('resize', layout);
  layout();

  function el(id) { return document.getElementById(id); }
  function set(id, v) { var e = el(id); if (e) e.textContent = v; }

  window.SwEvents = window.SwEvents || {};
  window.SwEvents.frame = function (d) {
    var now = performance.now();
    if (curT) interval = Math.max(16, Math.min(120, now - curT));
    prev = cur; cur = d.p; curT = now; nB = d.p.length / 2;
    preds = d.q || [];
    set('s-n', nB);
    set('s-ord', (d.o / 10).toFixed(1) + '%');
    var m = el('m-ord'); if (m) m.style.width = (d.o / 10) + '%';
    set('s-spd', (d.s / 100).toFixed(2));
    var bs = document.querySelectorAll('[data-mode]');
    for (var i = 0; i < bs.length; i++) bs[i].classList.toggle('on', Number(bs[i].getAttribute('data-mode')) === d.m);
    frames++;
  };
  window.SwEvents.presence = function (n) { set('s-view', n); };

  /* ---------- input: instant local cursor, throttled to the server ---------- */
  function world(ev) {
    var r = cv.getBoundingClientRect();
    return { x: ((ev.clientX - r.left) - ox) / sc, y: ((ev.clientY - r.top) - oy) / sc, sx: ev.clientX - r.left, sy: ev.clientY - r.top };
  }
  function send(force) {
    var now = performance.now();
    if (!force && now - me.sent < 30) return;
    me.sent = now;
    window.swSend('ptr', { x: Math.min(1, Math.max(0, me.x / WW)), y: Math.min(1, Math.max(0, me.y / WH)), k: me.down ? 1 : 0 });
  }
  cv.addEventListener('pointermove', function (ev) { var w = world(ev); me.x = w.x; me.y = w.y; me.sx = w.sx; me.sy = w.sy; send(false); });
  cv.addEventListener('pointerdown', function (ev) {
    var w = world(ev); me.x = w.x; me.y = w.y; me.sx = w.sx; me.sy = w.sy; me.down = true;
    try { cv.setPointerCapture(ev.pointerId); } catch (e) {} send(true);
  });
  cv.addEventListener('pointerup', function () { me.down = false; send(true); });
  cv.addEventListener('pointerleave', function () { if (!me.down) { me.x = me.y = -1; } });
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target.closest('[data-mode],[data-blast]') : null;
    if (!t) return;
    if (t.hasAttribute('data-mode')) {
      var m = Number(t.getAttribute('data-mode'));
      var bs = document.querySelectorAll('[data-mode]');
      for (var i = 0; i < bs.length; i++) bs[i].classList.toggle('on', Number(bs[i].getAttribute('data-mode')) === m);
      window.swSend('mode', { m: m });
    } else {
      var bx = me.x >= 0 ? me.x : WW / 2, by = me.y >= 0 ? me.y : WH / 2;
      rings.push({ x: bx, y: by, t: performance.now(), hue: 20 });
      window.swSend('blast', { x: bx / WW, y: by / WH });
    }
  });

  /* ---------- draw ---------- */
  function frame(now) {
    requestAnimationFrame(frame);
    if (now - fpsT > 1000) { set('s-fps', Math.round(frames * 1000 / (now - fpsT))); frames = 0; fpsT = now; }
    /* fading trails */
    g.globalCompositeOperation = 'source-over';
    g.fillStyle = 'rgba(6,7,10,0.2)'; g.fillRect(0, 0, W, H);
    if (!cur) return;
    var t = prev ? Math.min(1.2, (now - curT) / interval) : 1;
    g.globalCompositeOperation = 'lighter';
    var n = nB, i, x, y, dx, dy, a, c, s, sz = Math.max(4.5, 6.5 * sc);
    for (i = 0; i < n; i++) {
      var cx = cur[i * 2], cy = cur[i * 2 + 1];
      dx = 0; dy = 0;
      if (prev) {
        dx = cx - prev[i * 2]; dy = cy - prev[i * 2 + 1];
        if (dx > WW / 2 || dx < -WW / 2 || dy > WH / 2 || dy < -WH / 2) { dx = 0; dy = 0; }
      }
      x = ox + (cx + dx * (t - 1)) * sc; y = oy + (cy + dy * (t - 1)) * sc;
      if (x < -20 || y < -20 || x > W + 20 || y > H + 20) continue;
      a = (dx === 0 && dy === 0) ? 0 : Math.atan2(dy, dx);
      var hue = ((a * 57.3) + 200 + (i % 37) * 3.2 + 360) % 360;
      c = Math.cos(a); s = Math.sin(a);
      g.fillStyle = 'hsla(' + hue + ',85%,62%,0.85)';
      g.beginPath();
      g.moveTo(x + c * sz, y + s * sz);
      g.lineTo(x - c * sz * 0.7 - s * sz * 0.5, y - s * sz * 0.7 + c * sz * 0.5);
      g.lineTo(x - c * sz * 0.7 + s * sz * 0.5, y - s * sz * 0.7 - c * sz * 0.5);
      g.closePath(); g.fill();
    }
    g.globalCompositeOperation = 'source-over';

    /* predators / attractors / blasts (from the server, so everyone sees everyone) */
    for (i = 0; i < preds.length; i++) {
      var p = preds[i], px = ox + p[0] * sc, py = oy + p[1] * sc, pulse = 0.5 + 0.5 * Math.sin(now / 150 + i);
      if (p[2] === 1) {
        for (var k = 0; k < 3; k++) {
          var rr = ((now / 9 + k * 40) % 120) * sc;
          g.strokeStyle = 'hsla(' + p[3] + ',90%,65%,' + (1 - rr / (120 * sc)) * 0.6 + ')'; g.lineWidth = 1.5;
          g.beginPath(); g.arc(px, py, 120 * sc - rr, 0, 6.283); g.stroke();
        }
        g.fillStyle = 'hsl(' + p[3] + ',90%,70%)'; g.beginPath(); g.arc(px, py, 5, 0, 6.283); g.fill();
      } else if (p[2] === 0) {
        g.strokeStyle = 'hsla(' + p[3] + ',90%,65%,0.55)'; g.lineWidth = 1.5; g.setLineDash([4, 5]);
        g.beginPath(); g.arc(px, py, 173 * sc * (0.96 + pulse * 0.04), 0, 6.283); g.stroke(); g.setLineDash([]);
        g.fillStyle = 'hsl(' + p[3] + ',90%,65%)'; g.beginPath(); g.arc(px, py, 4, 0, 6.283); g.fill();
      }
    }
    for (i = rings.length - 1; i >= 0; i--) {
      var b = rings[i], bp = (now - b.t) / 700;
      if (bp >= 1) { rings.splice(i, 1); continue; }
      g.strokeStyle = 'hsla(' + b.hue + ',100%,60%,' + (1 - bp) + ')'; g.lineWidth = 3 * (1 - bp) + 0.5;
      g.beginPath(); g.arc(ox + b.x * sc, oy + b.y * sc, 400 * sc * bp, 0, 6.283); g.stroke();
    }
    /* my own cursor: drawn locally so it never lags */
    if (me.x >= 0) {
      g.strokeStyle = me.down ? 'rgba(120,230,255,0.95)' : 'rgba(255,255,255,0.9)'; g.lineWidth = 1.5;
      g.beginPath(); g.arc(me.sx, me.sy, me.down ? 11 : 7, 0, 6.283); g.stroke();
    }
  }
  requestAnimationFrame(frame);
})();
