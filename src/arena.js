/* Swarm Arena — canvas renderer. Source of truth for src/ArenaJs.sw
   (regenerate with: python3 scripts/embed_js.py src/arena.js ArenaJs src/ArenaJs.sw).

   The server sends one compact frame every ~100ms:
     h  heat bucket 0..4 per agent        e  [[from,to],...] recent real messages
     ev [['k',i,pid] | ['u',i,pid,ms,gen]] kills and supervisor respawns
     p c r m tot b  processes, crashes, restarts, msgs/s, total msgs, burst
   Everything on screen is drawn from those; nothing is simulated. */
(function () {
  var N = 600, COLS = 30, ROWS = 20;
  /* ?slow=6 plays every effect 6x slower (the data is still live) */
  var SLOW = Number((location.search.match(/slow=([0-9.]+)/) || [0, 1])[1]) || 1;
  var cv = document.getElementById('stage');
  if (!cv) return;
  var g = cv.getContext('2d');
  var dpr = Math.min(2, window.devicePixelRatio || 1);
  var W = 0, H = 0, cell = 10, gx = 0, gy = 0, sup = { x: 0, y: 0 };

  var lvl = new Float32Array(N), target = new Uint8Array(N);
  var deadAt = new Float64Array(N), upAt = new Float64Array(N), hotAt = new Float64Array(N);
  var comets = [], rings = [], sparks = [], beams = [];
  var shake = 0, hover = -1, frames = 0, lastFrame = 0;
  var restartMs = [], logQ = [], logTotal = 0;

  function layout() {
    W = cv.clientWidth; H = cv.clientHeight;
    cv.width = W * dpr; cv.height = H * dpr;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    var top = 100, pad = 24, panel = W > 900 ? 340 : 0, aw = W - panel;
    cell = Math.floor(Math.min((aw - pad * 2) / COLS, (H - top - pad) / ROWS));
    gx = Math.floor((aw - cell * COLS) / 2);
    gy = top + Math.floor((H - top - pad - cell * ROWS) / 2);
    sup.x = gx + cell * COLS / 2; sup.y = 62;
  }
  window.addEventListener('resize', layout);
  layout();

  function cx(i) { return gx + (i % COLS) * cell + cell / 2; }
  function cy(i) { return gy + Math.floor(i / COLS) * cell + cell / 2; }

  /* ---------- effects ---------- */
  function explode(i, now) {
    deadAt[i] = now;
    rings.push({ x: cx(i), y: cy(i), t: now, c: '255,70,50', r: cell * 4, d: 700 * SLOW });
    for (var k = 0; k < 14; k++) {
      var a = Math.random() * 6.283, v = 40 + Math.random() * 120;
      sparks.push({ x: cx(i), y: cy(i), vx: Math.cos(a) * v, vy: Math.sin(a) * v, t: now, d: (500 + Math.random() * 400) * SLOW });
    }
    beams.push({ i: i, t: now, c: '255,70,50', out: true, d: 450 * SLOW });
  }
  function respawn(i, now) {
    upAt[i] = now; deadAt[i] = 0;
    rings.push({ x: cx(i), y: cy(i), t: now, c: '60,255,150', r: cell * 3, d: 650 * SLOW });
    beams.push({ i: i, t: now, c: '60,255,150', out: false, d: 450 * SLOW });
  }

  /* ---------- frames from the server ---------- */
  function addLog(cls, html) { logQ.push([cls, html]); logTotal++; }
  window.SwEvents = window.SwEvents || {};
  window.SwEvents.frame = function (d) {
    var now = performance.now(), i, k;
    if (d.h) for (i = 0; i < N && i < d.h.length; i++) target[i] = d.h[i];
    var E = d.e || [];
    for (k = 0; k < E.length; k++) {
      comets.push({ a: E[k][0], b: E[k][1], t: now + Math.random() * 90, d: 320 + Math.random() * 160, bow: (Math.random() - 0.5) * 80 });
      hotAt[E[k][1]] = now;
    }
    if (comets.length > 900) comets.splice(0, comets.length - 900);
    var V = d.ev || [], kills = 0;
    for (k = 0; k < V.length; k++) {
      var e = V[k];
      if (e[0] === 'k') { kills++; if (!deadAt[e[1]]) explode(e[1], now); addLog('k', 'killed #' + e[1] + ' ' + e[2]); }
      else {
        respawn(e[1], now);
        restartMs.push(e[3]); if (restartMs.length > 200) restartMs.shift();
        addLog('u', 'respawned #' + e[1] + ' ' + e[2] + ' in ' + e[3] + 'ms &middot; gen ' + e[4]);
      }
    }
    if (kills >= 8) shake = Math.max(shake, Math.min(14, kills / 4));
    stat('s-proc', d.p); stat('s-msgs', d.m); stat('s-tot', d.tot);
    stat('s-crash', d.c); stat('s-rest', d.r);
    var avg = 0; for (k = 0; k < restartMs.length; k++) avg += restartMs[k];
    stat('s-ms', restartMs.length ? (avg / restartMs.length).toFixed(1) + ' ms' : '-');
    setBurst(d.b);
    flushLog();
  };

  function fmt(n) { n = Math.round(n || 0); return n >= 1e6 ? (n / 1e6).toFixed(2) + 'M' : n >= 1e4 ? (n / 1e3).toFixed(1) + 'k' : String(n); }
  function stat(id, v) { var el = document.getElementById(id); if (el) el.textContent = typeof v === 'string' ? v : fmt(v); }
  function flushLog() {
    var el = document.getElementById('log'); if (!el || !logQ.length) return;
    var q = logQ; logQ = [];
    var extra = q.length > 10 ? q.length - 10 : 0, keep = q.slice(-10), html = '';
    for (var i = keep.length - 1; i >= 0; i--) html += '<div class="ln ' + keep[i][0] + '">' + keep[i][1] + '</div>';
    if (extra) html = '<div class="ln m">... and ' + extra + ' more</div>' + html;
    el.innerHTML = html + el.innerHTML;
    while (el.children.length > 16) el.removeChild(el.lastChild);
  }

  /* ---------- controls: instant, client-side feedback first ---------- */
  function setBurst(b) {
    var bs = document.querySelectorAll('[data-burst]');
    for (var i = 0; i < bs.length; i++) bs[i].classList.toggle('on', Number(bs[i].getAttribute('data-burst')) === b);
  }
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target.closest('[data-burst],[data-kill]') : null;
    if (!t) return;
    if (t.hasAttribute('data-burst')) {
      var b = Number(t.getAttribute('data-burst')); setBurst(b); window.swSend('burst', { n: b });
    } else {
      var k = Number(t.getAttribute('data-kill'));
      shake = Math.max(shake, k >= 200 ? 22 : 12);
      window.swSend('chaos', { k: k });
    }
  });
  function cellAt(ev) {
    var r = cv.getBoundingClientRect(), x = ev.clientX - r.left - gx, y = ev.clientY - r.top - gy;
    var c = Math.floor(x / cell), rw = Math.floor(y / cell);
    return (c < 0 || c >= COLS || rw < 0 || rw >= ROWS) ? -1 : rw * COLS + c;
  }
  cv.addEventListener('mousemove', function (ev) { hover = cellAt(ev); cv.style.cursor = hover >= 0 ? 'crosshair' : 'default'; });
  cv.addEventListener('mouseleave', function () { hover = -1; });
  cv.addEventListener('mousedown', function (ev) {
    var i = cellAt(ev); if (i < 0) return;
    explode(i, performance.now()); shake = Math.max(shake, 3);
    window.swSend('kill', { key: String(i) });
  });

  /* ---------- draw loop ---------- */
  function mix(a, b, t) { return Math.round(a + (b - a) * t); }
  var RAMP = [[14, 18, 23], [18, 48, 74], [22, 89, 160], [24, 160, 216], [154, 240, 255]];
  function heatColor(l) {
    l = Math.max(0, Math.min(3.999, l));
    var i = Math.floor(l), t = l - i, a = RAMP[i], b = RAMP[i + 1];
    return 'rgb(' + mix(a[0], b[0], t) + ',' + mix(a[1], b[1], t) + ',' + mix(a[2], b[2], t) + ')';
  }
  function frame(now) {
    requestAnimationFrame(frame);
    var dt = Math.min(0.05, (now - (lastFrame || now)) / 1000); lastFrame = now; frames++;
    g.save();
    g.clearRect(0, 0, W, H);
    if (shake > 0.2) { g.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake); shake *= 0.9; } else shake = 0;

    /* supervisor node */
    var pulse = 0.5 + 0.5 * Math.sin(now / 400);
    g.beginPath(); g.arc(sup.x, sup.y, 20 + pulse * 2, 0, 6.283);
    g.strokeStyle = 'rgba(180,200,255,' + (0.35 + pulse * 0.2) + ')'; g.lineWidth = 1.5; g.stroke();
    g.beginPath(); g.arc(sup.x, sup.y, 5, 0, 6.283); g.fillStyle = '#c7d2fe'; g.fill();
    g.fillStyle = 'rgba(200,210,255,0.7)'; g.font = '10px ui-monospace,Menlo,monospace'; g.textAlign = 'center';
    g.fillText('SUPERVISOR', sup.x, sup.y + 38);

    /* cells */
    var i, x, y, s = cell * 0.8, off = (cell - s) / 2;
    for (i = 0; i < N; i++) {
      lvl[i] += (target[i] - lvl[i]) * Math.min(1, dt * 9);
      x = gx + (i % COLS) * cell + off; y = gy + Math.floor(i / COLS) * cell + off;
      var dead = deadAt[i] && now - deadAt[i] < 1500 * SLOW;
      if (dead) {
        var f = 1 - Math.min(1, (now - deadAt[i]) / (1500 * SLOW));
        g.fillStyle = 'rgba(255,60,40,' + (0.15 + f * 0.8) + ')'; g.fillRect(x, y, s, s);
        g.strokeStyle = 'rgba(0,0,0,0.7)'; g.beginPath(); g.moveTo(x, y); g.lineTo(x + s, y + s); g.moveTo(x + s, y); g.lineTo(x, y + s); g.stroke();
        continue;
      }
      g.fillStyle = heatColor(lvl[i]); g.fillRect(x, y, s, s);
      var up = upAt[i] ? 1 - (now - upAt[i]) / (900 * SLOW) : 0;
      if (up > 0) { g.fillStyle = 'rgba(120,255,180,' + up * 0.85 + ')'; g.fillRect(x, y, s, s); }
    }
    /* glow on the hot ones */
    g.globalCompositeOperation = 'lighter';
    for (i = 0; i < N; i++) {
      if (lvl[i] < 2.4) continue;
      var a = (lvl[i] - 2.4) / 1.6 * 0.45;
      var gr = g.createRadialGradient(cx(i), cy(i), 0, cx(i), cy(i), cell * 1.6);
      gr.addColorStop(0, 'rgba(90,215,240,' + a + ')'); gr.addColorStop(1, 'rgba(90,215,240,0)');
      g.fillStyle = gr; g.fillRect(cx(i) - cell * 1.6, cy(i) - cell * 1.6, cell * 3.2, cell * 3.2);
    }

    /* real message comets: from -> to along a bowed arc, with a tail */
    for (i = comets.length - 1; i >= 0; i--) {
      var c = comets[i], p = (now - c.t) / c.d;
      if (p < 0) continue;
      if (p >= 1) { comets.splice(i, 1); continue; }
      var x0 = cx(c.a), y0 = cy(c.a), x1 = cx(c.b), y1 = cy(c.b);
      var mx = (x0 + x1) / 2 + c.bow, my = (y0 + y1) / 2 - Math.abs(c.bow);
      for (var tl = 0; tl < 4; tl++) {
        var q = Math.max(0, p - tl * 0.04), u = 1 - q;
        var px = u * u * x0 + 2 * u * q * mx + q * q * x1, py = u * u * y0 + 2 * u * q * my + q * q * y1;
        g.fillStyle = 'rgba(160,235,255,' + (0.75 - tl * 0.18) * (1 - p * 0.4) + ')';
        g.beginPath(); g.arc(px, py, 2.1 - tl * 0.35, 0, 6.283); g.fill();
      }
    }

    /* supervisor beams: red out on death, green back on respawn */
    for (i = beams.length - 1; i >= 0; i--) {
      var b = beams[i], bp = (now - b.t) / b.d;
      if (bp >= 1) { beams.splice(i, 1); continue; }
      var ax = b.out ? cx(b.i) : sup.x, ay = b.out ? cy(b.i) : sup.y;
      var bx = b.out ? sup.x : cx(b.i), by = b.out ? sup.y : cy(b.i);
      var hx = ax + (bx - ax) * bp, hy = ay + (by - ay) * bp;
      g.strokeStyle = 'rgba(' + b.c + ',' + (0.55 * (1 - bp)) + ')'; g.lineWidth = 1.2;
      g.beginPath(); g.moveTo(ax, ay); g.lineTo(hx, hy); g.stroke();
      g.fillStyle = 'rgba(' + b.c + ',' + (1 - bp) + ')'; g.beginPath(); g.arc(hx, hy, 2.6, 0, 6.283); g.fill();
    }
    g.globalCompositeOperation = 'source-over';

    /* shockwave rings + sparks */
    for (i = rings.length - 1; i >= 0; i--) {
      var rg = rings[i], rp = (now - rg.t) / rg.d;
      if (rp >= 1) { rings.splice(i, 1); continue; }
      g.strokeStyle = 'rgba(' + rg.c + ',' + (1 - rp) + ')'; g.lineWidth = 3 * (1 - rp) + 0.5;
      g.beginPath(); g.arc(rg.x, rg.y, rg.r * rp, 0, 6.283); g.stroke();
    }
    for (i = sparks.length - 1; i >= 0; i--) {
      var sp = sparks[i], spp = (now - sp.t) / sp.d;
      if (spp >= 1) { sparks.splice(i, 1); continue; }
      var tt = (now - sp.t) / 1000 / SLOW;
      g.fillStyle = 'rgba(255,' + mix(200, 70, spp) + ',60,' + (1 - spp) + ')';
      g.fillRect(sp.x + sp.vx * tt, sp.y + sp.vy * tt + 60 * tt * tt, 2.4, 2.4);
    }

    /* hover label */
    if (hover >= 0) {
      g.strokeStyle = 'rgba(255,255,255,0.9)'; g.lineWidth = 1.5;
      g.strokeRect(gx + (hover % COLS) * cell + 1, gy + Math.floor(hover / COLS) * cell + 1, cell - 2, cell - 2);
      g.fillStyle = '#fff'; g.font = '11px ui-monospace,Menlo,monospace'; g.textAlign = 'left';
      g.fillText('agent #' + hover + ' - click to kill', Math.min(W - 160, cx(hover) + 10), Math.max(14, cy(hover) - 10));
    }
    g.restore();
  }
  requestAnimationFrame(frame);
})();
