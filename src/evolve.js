/* Evolution - client. Source of truth for src/EvolveJs.sw
   (python3 scripts/embed_js.py src/evolve.js EvolveJs src/EvolveJs.sw).

   One frame per 25 ms tick:
     cr   one row per creature:
          [slot, id, gen, hue, x, y, hx, hy, energy, health, speed*100, sight*100, brain size, age, eaten,
           autopilot share*1000, brain-vs-expert*1000, caution*100, hunger, poison hits, bites]
     sel  the slot whose brain is shown      s   local ids of its neurons that spiked
     mo / ex   its motor flags and the expert's     rays [[dist*1000, type]]   tw  strongest learned synapses
     food poison pred obst   the world        mean [speed, sight, brain, caution, hunger]  population means
     evs  life events: [7 slot hue gen m speed] birth, [4|5 slot hue gen age eaten] starved / slain
   Every neuron of every creature is a real swarmrt process; a spike is a message. Nothing is simulated. */
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var ac = $('arena-cv'), bc = $('brain-cv'), tc = $('chart-cv'), pc = $('pop-cv'), apane = $('arena'), bpane = $('brain');
  if (!ac) return;
  var ag = ac.getContext('2d'), bg = bc.getContext('2d'), tg = tc.getContext('2d'), pg = pc.getContext('2d');
  var dpr = Math.min(2, window.devicePixelRatio || 1);
  var AW = 0, AH = 0, BW = 0, BH = 0, N = 0, X = null, Y = null, act = null;
  var last = null, framesN = 0, fps = 0, fpsT = performance.now(), histT = 0, tw = [], rings = [], stats = {};
  var thist = [[], [], [], [], []], phist = [], motorAct = [0, 0, 0, 0], sel = -1;
  var TYPE_COL = [[80, 227, 194], [190, 110, 255], [255, 80, 80], [140, 150, 165]];
  var MCOL = [[90, 200, 255], [255, 170, 90], [255, 120, 190], [245, 220, 80]];
  var MNAME = ['forward', 'turn +', 'turn -', 'boost'];
  var REGION = [{ name: 'visual', c: [80, 160, 255] }, { name: 'chemical', c: [80, 227, 194] }, { name: 'association', c: [190, 140, 255] }];
  var TRAITS = [{ n: 'speed', lo: 60, hi: 180, c: [90, 200, 255] }, { n: 'sight', lo: 20, hi: 60, c: [80, 227, 194] }, { n: 'brain size', lo: 90, hi: 450, c: [190, 140, 255] }, { n: 'caution', lo: 40, hi: 180, c: [245, 166, 35] }, { n: 'hunger', lo: 40, hi: 98, c: [255, 120, 190] }];
  var geo = {}, arena = { s: 1, ox: 0, oy: 0 };

  function fmt(n) { n = Math.round(n || 0); if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k'; return String(n); }
  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }
  function rgba(c, a) { return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }
  function hsl(h, s, l, a) { return 'hsla(' + h + ',' + s + '%,' + l + '%,' + (a === undefined ? 1 : a) + ')'; }

  /* ---------- sizing ---------- */
  function resize() {
    AW = apane.clientWidth; AH = apane.clientHeight; BW = bpane.clientWidth; BH = bpane.clientHeight;
    ac.width = AW * dpr; ac.height = AH * dpr; ac.style.width = AW + 'px'; ac.style.height = AH + 'px'; ag.setTransform(dpr, 0, 0, dpr, 0, 0);
    bc.width = BW * dpr; bc.height = BH * dpr; bc.style.width = BW + 'px'; bc.style.height = BH + 'px'; bg.setTransform(dpr, 0, 0, dpr, 0, 0);
    var w1 = tc.clientWidth, h1 = tc.clientHeight; tc.width = w1 * dpr; tc.height = h1 * dpr; tg.setTransform(dpr, 0, 0, dpr, 0, 0);
    var w2 = pc.clientWidth, h2 = pc.clientHeight; pc.width = w2 * dpr; pc.height = h2 * dpr; pg.setTransform(dpr, 0, 0, dpr, 0, 0);
    var side = Math.max(120, Math.min(AW - 24, AH - 46));
    arena.s = side; arena.ox = (AW - side) / 2; arena.oy = 36;
    place();
  }
  function place() {
    var m = Math.min(BW, BH);
    geo.reg = [{ cx: BW * 0.30, cy: BH * 0.27, r: m * 0.17 }, { cx: BW * 0.30, cy: BH * 0.73, r: m * 0.15 }, { cx: BW * 0.62, cy: BH * 0.50, r: m * 0.22 }];
    geo.motor = []; for (var k = 0; k < 4; k++) geo.motor.push([BW - 56, BH * (0.2 + k * 0.2)]);
    geo.retina = []; for (var q = 0; q < 7; q++) geo.retina.push([26, BH * 0.27 + (q - 3) * (m * 0.062)]);
    layoutNeurons();
  }
  function layoutNeurons() {
    if (!N || !geo.reg) return;
    X = new Float32Array(N); Y = new Float32Array(N);
    var per = N / 3;
    for (var i = 0; i < N; i++) {
      var r = Math.min(2, Math.floor(i / per)), li = i - r * per, R = geo.reg[r].r;
      var rr = R * Math.sqrt((li + 0.5) / per), a = li * 2.399963;
      X[i] = geo.reg[r].cx + rr * Math.cos(a); Y[i] = geo.reg[r].cy + rr * Math.sin(a);
    }
  }
  if (window.ResizeObserver) { new ResizeObserver(resize).observe(apane); new ResizeObserver(resize).observe(bpane); } else window.addEventListener('resize', resize);

  /* ---------- frames ---------- */
  window.SwEvents = window.SwEvents || {};
  var EVCOL = { 7: '80,227,194', 4: '245,166,35', 5: '255,90,90' };
  window.SwEvents.frame = function (d) {
    var i, now = performance.now();
    last = d; framesN++;
    var selRow = rowOf(d.sel);
    var m = selRow ? selRow[12] : 0;
    if (d.sel !== sel || m !== N) { sel = d.sel; N = m; act = new Float32Array(N); tw = []; layoutNeurons(); }
    for (i = 0; i < d.s.length; i++) if (d.s[i] < N) act[d.s[i]] = 1;
    for (i = 0; i < 4; i++) if (d.mo[i]) motorAct[i] = 1;
    if (d.tw && d.tw.length) tw = d.tw;
    for (i = 0; i < d.evs.length; i++) addLog(d.evs[i]);
    if (now - histT > 1000) {
      histT = now;
      for (i = 0; i < 5; i++) { thist[i].push((d.mean[i] - TRAITS[i].lo) / (TRAITS[i].hi - TRAITS[i].lo)); if (thist[i].length > 120) thist[i].shift(); }
      phist.push(d.pop); if (phist.length > 120) phist.shift();
    }
    stat('pop', d.pop, fmtc, 'max 10 creatures', d.pop < 3 ? 'warn' : 'up');
    stat('gen', d.maxgen, fmtc, 'generations since the founders', '');
    stat('procs', d.procs, fmtc, d.pop ? 'about ' + Math.round((d.procs - 40) / d.pop) + ' per brain' : '', '');
    stat('rec', d.record / 40, function (x) { return x.toFixed(0) + 's'; }, 'oldest creature ever', 'up');
    stat('birth', d.births, fmtc, 'children born', 'up');
    stat('death', d.deaths, fmtc, d.starved + ' starved, ' + d.slain + ' slain', d.deaths ? 'bad' : '');
    var ah = $('ah'); if (ah) ah.innerHTML = '<b>' + d.pop + '</b> creatures &middot; click one to see its brain';
    var bh = $('bh'); if (bh) bh.innerHTML = selRow ? '<b>creature #' + selRow[1] + '</b> &middot; generation ' + selRow[2] + ' &middot; ' + fmtc(N) + ' neurons &middot; speed ' + (selRow[10] / 100).toFixed(2) + ', sight ' + (selRow[11] / 100).toFixed(2) + ', caution ' + (selRow[17] / 100).toFixed(2) : 'no creature';
    var hp = $('h-pop'); if (hp) hp.textContent = d.pop + ' alive';
    var ht = $('h-traits'); if (ht) ht.innerHTML = TRAITS.map(function (t, k) { var v = d.mean[k]; return '<span style="color:' + rgba(t.c, 1) + '">' + t.n + ' ' + (k === 2 || k === 4 ? Math.round(v) : (v / 100).toFixed(2)) + '</span>'; }).join(' &middot; ');
    tog('b-learn', 'Plasticity: ', d.learn); tog('b-pred', 'Predator: ', d.pred_on); var sb = document.querySelectorAll('[data-speed]'); for (i = 0; i < sb.length; i++) sb[i].classList.toggle('on', Number(sb[i].getAttribute('data-speed')) === Math.max(1, d.speed));
    renderBoard(d);
  };
  function rowOf(slot) { if (!last) return null; for (var i = 0; i < last.cr.length; i++) if (last.cr[i][0] === slot) return last.cr[i]; return null; }
  function tog(id, label, on) { var b = $(id); if (b) { b.textContent = label + (on ? 'on' : 'off'); b.classList.toggle('on', !!on); } }

  function addLog(e) {
    var el = $('log'); if (!el) return;
    var col = hsl(e[2], 80, 60, 1), txt;
    if (e[0] === 7) txt = 'Born: generation ' + e[3] + ', brain ' + e[4] + ', speed ' + (e[5] / 100).toFixed(2);
    else txt = (e[0] === 4 ? 'Starved' : 'Slain by the predator') + ' after ' + Math.round(e[4] / 40) + 's (ate ' + e[5] + ', gen ' + e[3] + ')';
    var row = document.createElement('div'); row.className = 'ev';
    row.innerHTML = '<i style="background:' + col + ';box-shadow:0 0 0 2px rgba(' + (EVCOL[e[0]] || '255,255,255') + ',0.5)"></i><span>' + txt + '</span>';
    el.insertBefore(row, el.firstChild); while (el.children.length > 8) el.removeChild(el.lastChild);
  }
  function renderBoard(d) {
    var el = $('lb'); if (!el) return;
    var rows = d.cr.slice().sort(function (a, b) { return b[13] - a[13]; }).slice(0, 5), h = '';
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      h += '<div class="lr" data-slot="' + c[0] + '"><i style="background:' + hsl(c[3], 80, 60, 1) + '"></i><span>gen ' + c[2] + ' &middot; brain ' + c[12] + ' &middot; speed ' + (c[10] / 100).toFixed(2) + '</span><b>' + Math.round(c[13] / 40) + 's &middot; ate ' + c[14] + '</b></div>';
    }
    el.innerHTML = h || '<span style="color:#666">no creatures</span>';
  }

  /* ---------- counters ---------- */
  function stat(id, v, f, sub, tone) {
    var s = stats[id] || (stats[id] = { cur: v, tgt: v, shown: '' }); s.tgt = v; s.fmt = f;
    var d = $('d-' + id); if (d) { d.textContent = sub; d.className = 'chip ' + (tone || ''); }
  }
  function tickStats() {
    for (var id in stats) {
      var s = stats[id]; s.cur += (s.tgt - s.cur) * 0.2; if (Math.abs(s.tgt - s.cur) < 0.3) s.cur = s.tgt;
      var t = s.fmt(s.cur), el = $('v-' + id); if (el && t !== s.shown) { el.textContent = t; s.shown = t; }
    }
  }

  /* ---------- controls ---------- */
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target.closest('[data-slot],[data-speed],#b-learn,#b-pred,#b-reset') : null;
    if (!t) return;
    if (t.hasAttribute('data-slot')) window.swSend('sel', { slot: Number(t.getAttribute('data-slot')) });
    else if (t.hasAttribute('data-speed')) window.swSend('speed', { k: Number(t.getAttribute('data-speed')) });
    else if (t.id === 'b-learn') window.swSend('learn', {});
    else if (t.id === 'b-pred') window.swSend('pred', {});
    else if (t.id === 'b-reset') { thist = [[], [], [], [], []]; phist = []; window.swSend('reset', {}); }
  });
  ac.addEventListener('mousedown', function (e) {
    if (!last) return;
    var r = ac.getBoundingClientRect(), mx = (e.clientX - r.left - arena.ox) / arena.s, my = (e.clientY - r.top - arena.oy) / arena.s, best = -1, bd = 0.06 * 0.06;
    for (var i = 0; i < last.cr.length; i++) { var c = last.cr[i], dx = c[4] / 1000 - mx, dy = c[5] / 1000 - my, d2 = dx * dx + dy * dy; if (d2 < bd) { bd = d2; best = c[0]; } }
    if (best >= 0) window.swSend('sel', { slot: best });
  });

  /* ---------- draw: the world ---------- */
  function ax(u) { return arena.ox + u * arena.s; }
  function ay(u) { return arena.oy + u * arena.s; }
  function drawArena(now) {
    ag.clearRect(0, 0, AW, AH);
    var S = arena.s;
    ag.fillStyle = '#06070a'; ag.fillRect(arena.ox, arena.oy, S, S);
    ag.strokeStyle = 'rgba(255,255,255,0.06)'; ag.lineWidth = 1;
    for (var q = 0; q <= 8; q++) { ag.beginPath(); ag.moveTo(ax(q / 8), ay(0)); ag.lineTo(ax(q / 8), ay(1)); ag.moveTo(ax(0), ay(q / 8)); ag.lineTo(ax(1), ay(q / 8)); ag.stroke(); }
    ag.strokeStyle = 'rgba(255,255,255,0.18)'; ag.strokeRect(arena.ox, arena.oy, S, S);
    if (!last) return;
    var d = last, i, pulse = 0.5 + 0.5 * Math.sin(now / 260);
    for (i = 0; i < d.obst.length; i++) { var o = d.obst[i]; ag.fillStyle = 'rgba(120,130,150,0.22)'; ag.strokeStyle = 'rgba(160,170,190,0.45)'; ag.beginPath(); ag.arc(ax(o[0] / 1000), ay(o[1] / 1000), o[2] / 1000 * S, 0, 6.2832); ag.fill(); ag.stroke(); }
    for (i = 0; i < d.food.length; i++) { var f = d.food[i], fx = ax(f[0] / 1000), fy = ay(f[1] / 1000); ag.fillStyle = 'rgba(80,227,194,' + (0.12 + pulse * 0.1) + ')'; ag.beginPath(); ag.arc(fx, fy, S * 0.028, 0, 6.2832); ag.fill(); ag.fillStyle = '#50e3c2'; ag.beginPath(); ag.arc(fx, fy, S * 0.011, 0, 6.2832); ag.fill(); }
    for (i = 0; i < d.poison.length; i++) {
      var p = d.poison[i], px = ax(p[0] / 1000), py = ay(p[1] / 1000);
      ag.fillStyle = 'rgba(190,110,255,' + (0.14 + pulse * 0.1) + ')'; ag.beginPath(); ag.arc(px, py, S * 0.032, 0, 6.2832); ag.fill();
      ag.strokeStyle = '#be6eff'; ag.lineWidth = 1.5; ag.beginPath(); ag.arc(px, py, S * 0.013, 0, 6.2832); ag.stroke();
      ag.beginPath(); ag.moveTo(px - S * 0.008, py - S * 0.008); ag.lineTo(px + S * 0.008, py + S * 0.008); ag.moveTo(px + S * 0.008, py - S * 0.008); ag.lineTo(px - S * 0.008, py + S * 0.008); ag.stroke();
    }
    if (d.pred_on) {
      var pr = d.pred, qx = ax(pr[0] / 1000), qy = ay(pr[1] / 1000), mode = pr[2], pcol = mode === 1 ? [255, 70, 70] : mode === 2 ? [140, 80, 80] : [255, 150, 90];
      var gr = ag.createRadialGradient(qx, qy, 0, qx, qy, S * (mode === 1 ? 0.09 : 0.06)); gr.addColorStop(0, rgba(pcol, mode === 1 ? 0.5 : 0.25)); gr.addColorStop(1, rgba(pcol, 0));
      ag.fillStyle = gr; ag.fillRect(qx - S * 0.1, qy - S * 0.1, S * 0.2, S * 0.2);
      ag.fillStyle = rgba(pcol, 1); ag.beginPath(); ag.arc(qx, qy, S * 0.02, 0, 6.2832); ag.fill();
    }
    /* the selected creature's vision rays */
    var cs = [[0.5, -0.866], [0.766, -0.643], [0.94, -0.342], [1, 0], [0.94, 0.342], [0.766, 0.643], [0.5, 0.866]];
    var sr = rowOf(d.sel);
    if (sr && d.rays.length) {
      var scx = ax(sr[4] / 1000), scy = ay(sr[5] / 1000), shx = sr[6] / 1000, shy = sr[7] / 1000, vis = sr[11] / 100;
      for (i = 0; i < 7; i++) {
        var rdx = shx * cs[i][0] - shy * cs[i][1], rdy = shx * cs[i][1] + shy * cs[i][0], dist = Math.min(vis, d.rays[i][0] / 1000), hit = d.rays[i][0] / 1000 <= vis, col = TYPE_COL[d.rays[i][1]];
        ag.strokeStyle = rgba(col, hit ? 0.5 : 0.1); ag.lineWidth = hit ? 1.2 : 0.7; ag.beginPath(); ag.moveTo(scx, scy); ag.lineTo(scx + rdx * dist * S, scy + rdy * dist * S); ag.stroke();
      }
    }
    for (i = 0; i < d.cr.length; i++) {
      var c = d.cr[i], cx = ax(c[4] / 1000), cy = ay(c[5] / 1000), hx = c[6] / 1000, hy = c[7] / 1000, isSel = c[0] === d.sel;
      var rad = S * (0.012 + 0.006 * (c[10] / 100 - 0.6) / 1.2);
      var g2 = ag.createRadialGradient(cx, cy, 0, cx, cy, rad * 3); g2.addColorStop(0, hsl(c[3], 85, 60, isSel ? 0.55 : 0.3)); g2.addColorStop(1, hsl(c[3], 85, 60, 0));
      ag.fillStyle = g2; ag.fillRect(cx - rad * 3, cy - rad * 3, rad * 6, rad * 6);
      ag.fillStyle = hsl(c[3], 85, 62, 1); ag.beginPath(); ag.arc(cx, cy, rad, 0, 6.2832); ag.fill();
      ag.strokeStyle = 'rgba(255,255,255,0.9)'; ag.lineWidth = 1.5; ag.beginPath(); ag.moveTo(cx, cy); ag.lineTo(cx + hx * rad * 1.9, cy + hy * rad * 1.9); ag.stroke();
      /* energy ring */
      ag.strokeStyle = c[8] > 40 ? 'rgba(80,227,194,0.85)' : 'rgba(245,166,35,0.9)'; ag.lineWidth = 2; ag.beginPath(); ag.arc(cx, cy, rad + 3.5, -1.57, -1.57 + 6.2832 * Math.max(0, c[8]) / 100); ag.stroke();
      if (isSel) { ag.strokeStyle = '#fff'; ag.lineWidth = 1; ag.beginPath(); ag.arc(cx, cy, rad + 8 + Math.sin(now / 250), 0, 6.2832); ag.stroke(); }
    }
  }

  /* ---------- draw: the selected creature's brain ---------- */
  function drawBrain(now) {
    bg.clearRect(0, 0, BW, BH);
    if (!N || !X || !act) return;
    var i, r, m, k, per = N / 3;
    for (r = 0; r < 3; r++) {
      var rg = geo.reg[r];
      bg.strokeStyle = rgba(REGION[r].c, 0.18); bg.lineWidth = 1; bg.beginPath(); bg.arc(rg.cx, rg.cy, rg.r + 8, 0, 6.2832); bg.stroke();
      bg.fillStyle = rgba(REGION[r].c, 0.85); bg.font = '500 11px ui-sans-serif,-apple-system,sans-serif'; bg.textAlign = 'center'; bg.fillText(REGION[r].name, rg.cx, rg.cy - rg.r - 14);
    }
    for (i = 0; i < N; i++) {
      var reg = Math.min(2, Math.floor(i / per));
      bg.fillStyle = rgba(REGION[reg].c, 0.24); bg.fillRect(X[i] - 0.9, Y[i] - 0.9, 1.8, 1.8);
      if (act[i] > 0.04) act[i] *= 0.86; else act[i] = 0;
    }
    bg.globalCompositeOperation = 'lighter';
    for (i = 0; i < N; i++) {
      var b = act[i];
      if (b > 0.05) { var c = REGION[Math.min(2, Math.floor(i / per))].c; bg.fillStyle = rgba([Math.min(255, c[0] + 90), Math.min(255, c[1] + 70), 255], b * 0.9); bg.beginPath(); bg.arc(X[i], Y[i], 1.2 + b * 2.6, 0, 6.2832); bg.fill(); }
    }
    for (k = 0; k < tw.length; k++) {
      var q = tw[k], mm = q[0], ni = q[1], w = q[2] / 100;
      if (ni >= N) continue;
      var m1 = geo.motor[mm], cxm = (X[ni] + m1[0]) / 2, cym = (Y[ni] + m1[1]) / 2 - 14;
      bg.strokeStyle = rgba(MCOL[mm], Math.min(0.5, 0.05 + w * 0.25 + act[ni] * 0.5)); bg.lineWidth = 0.6 + w * 0.4;
      bg.beginPath(); bg.moveTo(X[ni], Y[ni]); bg.quadraticCurveTo(cxm, cym, m1[0], m1[1]); bg.stroke();
    }
    bg.globalCompositeOperation = 'source-over';
    if (last && last.rays.length) {
      bg.font = '10px ui-sans-serif,-apple-system,sans-serif'; bg.textAlign = 'left'; bg.fillStyle = '#6b6b6b'; bg.fillText('retina', 12, geo.retina[0][1] - 20);
      var sr = rowOf(last.sel), vis = sr ? sr[11] / 100 : 0.45;
      for (i = 0; i < 7; i++) {
        var ry = last.rays[i], hitp = ry[0] / 1000 <= vis, cc2 = TYPE_COL[ry[1]], rp = geo.retina[i];
        bg.fillStyle = rgba(cc2, hitp ? 0.35 + 0.65 * (1 - ry[0] / (vis * 1000)) : 0.12); bg.fillRect(rp[0] - 8, rp[1] - 6, 16, 12);
      }
    }
    for (m = 0; m < 4; m++) {
      var mp = geo.motor[m], ma = motorAct[m]; motorAct[m] = ma * 0.9;
      var rr = 11 + ma * 5, g3 = bg.createRadialGradient(mp[0], mp[1], 0, mp[0], mp[1], rr * 3); g3.addColorStop(0, rgba(MCOL[m], 0.15 + ma * 0.5)); g3.addColorStop(1, rgba(MCOL[m], 0));
      bg.fillStyle = g3; bg.fillRect(mp[0] - rr * 3, mp[1] - rr * 3, rr * 6, rr * 6);
      bg.fillStyle = rgba(MCOL[m], 0.75 + ma * 0.25); bg.beginPath(); bg.arc(mp[0], mp[1], rr, 0, 6.2832); bg.fill();
      bg.fillStyle = '#ededed'; bg.textAlign = 'right'; bg.font = '500 10.5px ui-sans-serif,-apple-system,sans-serif'; bg.fillText(MNAME[m], mp[0] - rr - 8, mp[1] + 4);
      if (last) { var agree = !!last.mo[m] === !!last.ex[m]; bg.strokeStyle = last.ex[m] ? '#50e3c2' : 'rgba(255,255,255,0.25)'; bg.lineWidth = 1.5; bg.beginPath(); bg.arc(mp[0], mp[1] + rr + 9, 3.5, 0, 6.2832); bg.stroke(); bg.fillStyle = agree ? 'rgba(80,227,194,0.9)' : 'rgba(255,90,90,0.9)'; bg.beginPath(); bg.arc(mp[0], mp[1] + rr + 9, 1.8, 0, 6.2832); bg.fill(); }
    }
  }

  /* ---------- draw: charts ---------- */
  function drawTraits() {
    var w = tc.clientWidth, h = tc.clientHeight; tg.clearRect(0, 0, w, h);
    tg.strokeStyle = 'rgba(255,255,255,0.06)'; tg.lineWidth = 1;
    for (var q = 0; q <= 4; q++) { var y = 4 + q * (h - 8) / 4; tg.beginPath(); tg.moveTo(0, y); tg.lineTo(w, y); tg.stroke(); }
    for (var s = 0; s < 5; s++) {
      var arr = thist[s]; if (arr.length < 2) continue;
      tg.beginPath(); for (var i = 0; i < arr.length; i++) { var X1 = i / 119 * w, Y1 = h - 4 - Math.max(0, Math.min(1, arr[i])) * (h - 8); if (i === 0) tg.moveTo(X1, Y1); else tg.lineTo(X1, Y1); }
      tg.strokeStyle = rgba(TRAITS[s].c, 0.95); tg.lineWidth = 1.5; tg.stroke();
    }
  }
  function drawPop() {
    var w = pc.clientWidth, h = pc.clientHeight; pg.clearRect(0, 0, w, h);
    pg.strokeStyle = 'rgba(255,255,255,0.06)'; pg.lineWidth = 1;
    for (var q = 0; q <= 4; q++) { var y = 4 + q * (h - 8) / 4; pg.beginPath(); pg.moveTo(0, y); pg.lineTo(w, y); pg.stroke(); }
    if (phist.length < 2) return;
    function X1(i) { return i / 119 * w; } function Y1(v) { return h - 4 - (v / 10) * (h - 8); }
    var gr = pg.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, 'rgba(80,227,194,0.28)'); gr.addColorStop(1, 'rgba(80,227,194,0)');
    pg.beginPath(); pg.moveTo(X1(0), h); for (var i = 0; i < phist.length; i++) pg.lineTo(X1(i), Y1(phist[i])); pg.lineTo(X1(phist.length - 1), h); pg.closePath(); pg.fillStyle = gr; pg.fill();
    pg.beginPath(); for (var j = 0; j < phist.length; j++) { if (j === 0) pg.moveTo(X1(j), Y1(phist[j])); else pg.lineTo(X1(j), Y1(phist[j])); }
    pg.strokeStyle = '#50e3c2'; pg.lineWidth = 1.6; pg.stroke();
  }

  function frame(now) {
    requestAnimationFrame(frame);
    if (now - fpsT > 1000) { fps = framesN; framesN = 0; fpsT = now; var f = $('o-fps'); if (f) f.textContent = fps; }
    tickStats();
    if (!AW) { resize(); return; }
    drawArena(now); drawBrain(now); drawTraits(); drawPop();
  }
  window.__swEvolve = { get last() { return last; } };
  resize();
  requestAnimationFrame(frame);
})();
