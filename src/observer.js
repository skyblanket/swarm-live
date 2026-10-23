/* Swarm Observer - client. Source of truth for src/ObserverJs.sw
   (python3 scripts/embed_js.py src/observer.js ObserverJs src/ObserverJs.sw).

   ~4 frames/s from the server, sampled from the live node:
     n   process count          sc  scheduler count
     sch [[id, procs_run_delta, steals_delta, idle_waits_delta], ...]
     tot [spawns, crashes, restarts, dropped]   dl  the same, as deltas this frame
     p   [[pid, parent, status, mailbox, memKB, recv_delta, sent_delta, name], ...]
         status 0 waiting, 1 running, 2 runnable; name is 0 when unnamed
     k   1 if the server allows killing a process from the UI
   Everything is process_list / process_info / swarm_stats. Nothing is simulated. */
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var cv = $('map-cv');
  if (!cv) return;
  var g = cv.getContext('2d');
  var dpr = Math.min(2, window.devicePixelRatio || 1);
  var W = 0, H = 0;

  var COLORS = { run: [59, 158, 255], wait: [82, 90, 105], runnable: [245, 166, 35], red: [255, 77, 77], green: [80, 227, 194] };
  var procs = {}, groups = {}, ghosts = [], pops = [];
  var layoutDirty = true, structSig = '';
  var selected = 0, hover = 0, killable = 0, tab = 'mail';
  var last = null, lastT = 0, dt = 250, first = true, framesN = 0, fps = 0, fpsT = performance.now();
  var hist = { proc: [], msg: [], rs: [], cr: [], sch: [] };
  var selHist = { mail: [], mem: [], rate: [] };
  var stats = {};                       /* animated counters: id -> {cur, tgt, fmt} */
  var feed = [];

  /* ---------- helpers ---------- */
  function fmt(n) { n = Math.round(n || 0); if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'; if (n >= 1e4) return (n / 1e3).toFixed(1) + 'k'; return String(n); }
  function fmtc(n) { return Math.round(n || 0).toLocaleString('en-US'); }
  function kb(n) { return n >= 1024 ? (n / 1024).toFixed(1) + ' MB' : Math.round(n) + ' KB'; }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }
  function rgba(c, a) { return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }
  function ease(t) { return 1 - Math.pow(1 - t, 3); }
  function back(t) { var c1 = 1.9, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); }
  function label(p) { return p.name || ('process ' + p.pid); }
  function groupName(pid) {
    var c = groups[pid]; return c ? c.label : '#' + pid;
  }

  /* ---------- sizing ---------- */
  function resize() {
    var box = $('map'); if (!box) return;
    W = box.clientWidth; H = box.clientHeight;
    cv.width = Math.max(1, W * dpr); cv.height = Math.max(1, H * dpr);
    cv.style.width = W + 'px'; cv.style.height = H + 'px';
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    layoutDirty = true;
  }
  if (window.ResizeObserver) new ResizeObserver(resize).observe($('map')); else window.addEventListener('resize', resize);
  resize();

  /* ---------- cluster layout: phyllotaxis inside, spiral packing between ---------- */
  var SP = 9.2, GAP = 14;
  function slotPos(k) { var a = k * 2.399963, r = SP * Math.sqrt(k + 0.6); return [r * Math.cos(a), r * Math.sin(a)]; }
  function relayout() {
    var gs = [], key, i, j;
    for (key in groups) gs.push(groups[key]);
    if (!gs.length || W < 50) return;
    gs.forEach(function (c) { c.r = SP * Math.sqrt(c.cap + 1) + 10; c.tx = NaN; });
    gs.sort(function (a, b) { return b.r - a.r; });
    var placed = [];
    for (i = 0; i < gs.length; i++) {
      var c = gs[i], done = false;
      if (!placed.length) { c.tx = 0; c.ty = 0; placed.push(c); continue; }
      for (var rad = 0; !done && rad < 6000; rad += 5) {
        var steps = Math.max(12, Math.ceil(rad / 6));
        for (var s = 0; s < steps; s++) {
          var ang = s / steps * 6.2832, x = rad * Math.cos(ang), y = rad * Math.sin(ang), ok = true;
          for (j = 0; j < placed.length; j++) {
            var dx = x - placed[j].tx, dy = y - placed[j].ty;
            if (Math.sqrt(dx * dx + dy * dy) < c.r + placed[j].r + GAP) { ok = false; break; }
          }
          if (ok) { c.tx = x; c.ty = y; placed.push(c); done = true; break; }
        }
      }
      if (!done) { c.tx = 0; c.ty = 0; }
    }
    var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    gs.forEach(function (c) { x0 = Math.min(x0, c.tx - c.r); x1 = Math.max(x1, c.tx + c.r); y0 = Math.min(y0, c.ty - c.r - 22); y1 = Math.max(y1, c.ty + c.r); });
    var pad = 36, aw = W - pad * 2, ah = H - pad * 2 - 20;
    var sc = Math.max(0.2, Math.min(aw / Math.max(1, x1 - x0), ah / Math.max(1, y1 - y0), 2.4));
    var mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
    gs.forEach(function (c) {
      c.sx = W / 2 + (c.tx - mx) * sc; c.sy = H / 2 + 6 + (c.ty - my) * sc; c.sc = sc;
      if (c.x === undefined) { c.x = c.sx; c.y = c.sy; c.z = sc; }
    });
    layoutDirty = false;
  }

  /* ---------- slots ---------- */
  function assign(p) {
    var c = groups[p.parent];
    if (!c) { c = groups[p.parent] = { used: {}, cap: 0, n: 0, label: '', key: p.parent }; layoutDirty = true; }
    var k = 0; while (c.used[k]) k++;
    c.used[k] = p.pid; p.slot = k; c.n++;
    if (k + 1 > c.cap) c.cap = Math.max(k + 1, Math.ceil(c.cap * 1.3));
  }
  function release(p) {
    var c = groups[p.parent];
    if (c && p.slot >= 0) { delete c.used[p.slot]; c.n--; }
    p.slot = -1;
  }

  /* ---------- frames ---------- */
  window.SwEvents = window.SwEvents || {};
  window.SwEvents.obs = function (d) {
    var now = performance.now(), i, row, p, seen = {};
    if (lastT) dt = Math.max(100, Math.min(1000, now - lastT));
    lastT = now; last = d; killable = d.k || 0; framesN++;
    var births = {}, deaths = {};
    for (i = 0; i < d.p.length; i++) {
      row = d.p[i]; seen[row[0]] = 1; p = procs[row[0]];
      if (!p) { p = procs[row[0]] = { pid: row[0], heat: 0, slot: -1, born: now, parent: -1 }; if (!first) pops.push(p); }
      var par = row[1] || 0;
      if (p.parent !== par) {
        if (p.slot >= 0) release(p);
        var wasNew = p.parent === -1; p.parent = par;
        if (wasNew && !first) births[par] = (births[par] || 0) + 1;
      }
      p.status = row[2]; p.mail = row[3]; p.mem = row[4];
      p.recv = row[5] * 1000 / dt; p.sent = row[6] * 1000 / dt; p.rate = p.recv + p.sent; p.name = row[7] || '';
      p.heat += (Math.min(1, p.rate / 80) - p.heat) * 0.5;
      if (p.slot < 0) assign(p);
    }
    for (var pid in procs) {
      if (seen[pid]) continue;
      var q = procs[pid];
      ghosts.push({ x: q.px, y: q.py, t: now, c: d.dl[1] > 0 ? COLORS.red : COLORS.wait });
      deaths[q.parent] = (deaths[q.parent] || 0) + 1;
      release(q); delete procs[pid]; if (selected == pid) { selected = 0; selHist = { mail: [], mem: [], rate: [] }; }
    }
    for (var gk in groups) if (!groups[gk].n) { delete groups[gk]; layoutDirty = true; }
    for (gk in groups) {
      var par2 = procs[gk], nm = '';
      if (gk == 0) nm = 'node'; else if (par2 && par2.name && par2.name !== 'sw_dynsup') nm = par2.name; else nm = 'children of #' + gk;
      groups[gk].label = nm;
    }
    var sig = Object.keys(groups).map(function (k) { return k + ':' + groups[k].cap; }).join(',');
    if (sig !== structSig) { structSig = sig; layoutDirty = true; }

    /* activity feed: one plain-language line per group per frame */
    if (!first) {
      for (var b in births) addFeed('spawn', '<b>' + births[b] + '</b> spawned in <em>' + esc(groupName(b)) + '</em>');
      for (var x in deaths) {
        if (d.dl[1] > 0) addFeed('crash', '<b>' + deaths[x] + '</b> crashed in <em>' + esc(groupName(x)) + '</em>' + (d.dl[2] > 0 ? ', supervisor restarted ' + d.dl[2] : ''));
        else addFeed('exit', '<b>' + deaths[x] + '</b> exited in <em>' + esc(groupName(x)) + '</em>');
      }
    }

    /* history for the sparklines / inspector */
    var msgs = 0; for (i = 0; i < d.p.length; i++) msgs += d.p[i][5];
    push(hist.proc, d.n); push(hist.msg, msgs * 1000 / dt); push(hist.rs, d.dl[2] * 1000 / dt); push(hist.cr, d.dl[1] * 1000 / dt);
    var run = 0; for (i = 0; i < d.sch.length; i++) run += d.sch[i][1]; push(hist.sch, run * 1000 / dt);
    var sp = procs[selected]; if (sp) { push(selHist.mail, sp.mail); push(selHist.mem, sp.mem); push(selHist.rate, sp.rate); }

    setStat('proc', d.n, fmtc, d.dl[0] ? '+' + fmt(d.dl[0] * 1000 / dt) + ' spawned/s' : 'steady', d.dl[0] ? 'up' : '');
    setStat('msg', msgs * 1000 / dt, fmt, 'messages delivered / s', '');
    setStat('rs', d.tot[2], fmtc, d.dl[2] ? '+' + fmt(d.dl[2] * 1000 / dt) + '/s restarting' : 'supervisors idle', d.dl[2] ? 'warn' : '');
    setStat('cr', d.tot[1], fmtc, d.dl[1] ? '+' + fmt(d.dl[1] * 1000 / dt) + '/s crashing' : 'no crashes now', d.dl[1] ? 'bad' : '');
    setStat('sch', d.sc, fmtc, d.tot[3] ? fmt(d.tot[3]) + ' msgs dropped' : 'no messages dropped', d.tot[3] ? 'bad' : '');
    first = false;
    renderSide();
  };
  window.SwEvents.viewers = function (n) { if ($('o-view')) $('o-view').textContent = n; };
  function push(a, v) { a.push(v); if (a.length > 90) a.shift(); }

  /* ---------- animated counters ---------- */
  function setStat(id, v, f, sub, tone) {
    var s = stats[id] || (stats[id] = { cur: v, tgt: v, shown: '' });
    s.tgt = v; s.fmt = f;
    var d = $('d-' + id); if (d) { d.textContent = sub; d.className = 'chip ' + (tone || ''); }
  }
  function tickStats() {
    for (var id in stats) {
      var s = stats[id]; s.cur += (s.tgt - s.cur) * 0.2; if (Math.abs(s.tgt - s.cur) < 0.5) s.cur = s.tgt;
      var t = s.fmt(s.cur), el = $('v-' + id);
      if (el && t !== s.shown) { el.textContent = t; s.shown = t; }
    }
  }

  /* ---------- sparklines ---------- */
  function spark(id, arr, color) {
    var c = $(id); if (!c || arr.length < 2) return;
    var w = c.clientWidth, h = c.clientHeight, r = Math.min(2, window.devicePixelRatio || 1);
    if (c.width !== w * r) { c.width = w * r; c.height = h * r; }
    var x = c.getContext('2d'); x.setTransform(r, 0, 0, r, 0, 0); x.clearRect(0, 0, w, h);
    var lo = Math.min.apply(null, arr), hi = Math.max.apply(null, arr), n = arr.length, i;
    if (hi - lo < 1e-9) { hi = lo + 1; }
    function X(k) { return k / Math.max(1, n - 1) * w; }
    function Y(k) { return h - 4 - ((arr[k] - lo) / (hi - lo)) * (h - 10); }
    var gr = x.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, rgba(color, 0.28)); gr.addColorStop(1, rgba(color, 0));
    x.beginPath(); x.moveTo(0, h);
    for (i = 0; i < n; i++) x.lineTo(X(i), Y(i));
    x.lineTo(w, h); x.closePath(); x.fillStyle = gr; x.fill();
    x.beginPath(); for (i = 0; i < n; i++) { if (i === 0) x.moveTo(X(i), Y(i)); else x.lineTo(X(i), Y(i)); }
    x.strokeStyle = rgba(color, 0.95); x.lineWidth = 1.5; x.stroke();
  }

  /* ---------- side panels ---------- */
  function addFeed(kind, html) {
    feed.unshift({ kind: kind, html: html, t: Date.now() }); if (feed.length > 40) feed.pop();
    var el = $('o-feed'); if (!el) return;
    var d = document.createElement('div'); d.className = 'ev ' + kind; d.setAttribute('data-t', Date.now());
    d.innerHTML = '<i></i><span>' + html + '</span><time>now</time>';
    el.insertBefore(d, el.firstChild);
    while (el.children.length > 40) el.removeChild(el.lastChild);
  }
  function ageFeed() {
    var el = $('o-feed'); if (!el) return; var now = Date.now();
    for (var i = 0; i < el.children.length; i++) {
      var t = el.children[i].getAttribute('data-t'), s = Math.round((now - t) / 1000), tm = el.children[i].lastChild;
      if (tm) tm.textContent = s < 2 ? 'now' : s < 60 ? s + 's' : Math.floor(s / 60) + 'm';
    }
  }
  setInterval(ageFeed, 1000);

  function renderSide() {
    if (!last) return;
    var d = last, i, h = '';
    /* tabs */
    var arr = []; for (var pid in procs) arr.push(procs[pid]);
    var items, val, mxv = 1, sub;
    if (tab === 'mail') { items = arr.filter(function (p) { return p.mail >= 8; }).sort(function (a, b) { return b.mail - a.mail; }); val = function (p) { return p.mail; }; sub = function (p) { return fmtc(p.mail) + ' queued'; }; }
    else if (tab === 'hot') { items = arr.filter(function (p) { return p.rate > 0.5; }).sort(function (a, b) { return b.rate - a.rate; }); val = function (p) { return p.rate; }; sub = function (p) { return fmt(p.rate) + ' msg/s'; }; }
    else { items = arr.slice().sort(function (a, b) { return b.mem - a.mem; }); val = function (p) { return p.mem; }; sub = function (p) { return kb(p.mem); }; }
    items = items.slice(0, 6);
    if (items.length) mxv = Math.max(1, val(items[0]));
    for (i = 0; i < items.length; i++) {
      var p = items[i], w = Math.max(3, val(p) / mxv * 100);
      h += '<div class="li' + (p.pid == selected ? ' on' : '') + '" data-pid="' + p.pid + '"><div class="lt"><span>' + esc(p.name || ('process ' + p.pid)) + '</span><b>' + sub(p) + '</b></div>' +
           '<div class="bar"><i style="width:' + w + '%"></i></div><div class="ls">' + esc(groupName(p.parent)) + ' &middot; #' + p.pid + '</div></div>';
    }
    $('o-list').innerHTML = h || '<div class="empty">' + (tab === 'mail' ? 'No process has a backlog. Healthy.' : 'Nothing to show.') + '</div>';
    var tabs = document.querySelectorAll('[data-tab]');
    for (i = 0; i < tabs.length; i++) tabs[i].classList.toggle('on', tabs[i].getAttribute('data-tab') === tab);
    /* schedulers */
    var mxr = 1; for (i = 0; i < d.sch.length; i++) mxr = Math.max(mxr, d.sch[i][1]);
    h = '';
    for (i = 0; i < d.sch.length; i++) {
      var s = d.sch[i], busy = s[1] / mxr * 100;
      h += '<div class="sc"><span>S' + s[0] + '</span><div class="bar"><i style="width:' + Math.max(2, busy) + '%"></i></div><b>' + fmt(s[1] * 1000 / dt) + ' runs/s</b></div>';
    }
    $('o-sch').innerHTML = h;
    renderInspector();
    spark('sp-proc', hist.proc, COLORS.run); spark('sp-msg', hist.msg, COLORS.green); spark('sp-rs', hist.rs, COLORS.runnable);
    spark('sp-cr', hist.cr, COLORS.red); spark('sp-sch', hist.sch, COLORS.run);
    var vw = $('o-fps'); if (vw) vw.textContent = fps;
  }
  function renderInspector() {
    var box = $('o-insp'), p = procs[selected];
    if (!p) { box.innerHTML = '<div class="empty">Select a process on the map, or from a list, to inspect it.</div>'; return; }
    var st = ['waiting', 'running', 'runnable'][p.status] || '?', cls = ['wait', 'run', 'runnable'][p.status] || 'wait';
    var parent = procs[p.parent];
    box.innerHTML = '<div class="ih"><div><h4>' + esc(label(p)) + '</h4><div class="sub">#' + p.pid + (parent ? ' &middot; child of <a data-pid="' + parent.pid + '">' + esc(label(parent)) + '</a>' : '') + '</div></div><span class="pill ' + cls + '">' + st + '</span></div>' +
      '<div class="kv"><div><span>memory</span><b>' + kb(p.mem) + '</b></div><div><span>mailbox</span><b class="' + (p.mail > 100 ? 'bad' : '') + '">' + fmtc(p.mail) + '</b></div><div><span>in</span><b>' + fmt(p.recv) + '/s</b></div><div><span>out</span><b>' + fmt(p.sent) + '/s</b></div></div>' +
      '<div class="sparks2"><div><span>mailbox depth</span><canvas id="si-mail"></canvas></div><div><span>messages / s</span><canvas id="si-rate"></canvas></div></div>' +
      (killable ? '<button class="btn danger" id="o-kill">Kill process</button>' : '');
    spark('si-mail', selHist.mail, COLORS.red); spark('si-rate', selHist.rate, COLORS.run);
  }

  /* ---------- input ---------- */
  function pick(mx, my) {
    var best = 0, bd = 150;
    for (var pid in procs) {
      var p = procs[pid]; if (p.px === undefined) continue;
      var dx = mx - p.px, dy = my - p.py, d2 = dx * dx + dy * dy;
      if (d2 < bd) { bd = d2; best = p.pid; }
    }
    return best;
  }
  function select(pid) { selected = pid || 0; selHist = { mail: [], mem: [], rate: [] }; if (procs[selected]) { selHist.mail.push(procs[selected].mail); selHist.mem.push(procs[selected].mem); selHist.rate.push(procs[selected].rate); } renderSide(); }
  cv.addEventListener('mousemove', function (e) {
    var r = cv.getBoundingClientRect(); hover = pick(e.clientX - r.left, e.clientY - r.top); cv.style.cursor = hover ? 'pointer' : 'default';
    var tip = $('o-tip'), p = procs[hover];
    if (p && tip) {
      tip.style.display = 'block';
      tip.innerHTML = '<b>' + esc(label(p)) + '</b><span>#' + p.pid + ' &middot; ' + esc(groupName(p.parent)) + '</span><span>' + kb(p.mem) + ' &middot; mailbox ' + fmtc(p.mail) + ' &middot; ' + fmt(p.rate) + ' msg/s</span>';
      tip.style.left = Math.min(W - 230, e.clientX - r.left + 14) + 'px'; tip.style.top = Math.max(8, e.clientY - r.top - 12) + 'px';
    } else if (tip) tip.style.display = 'none';
  });
  cv.addEventListener('mouseleave', function () { hover = 0; var t = $('o-tip'); if (t) t.style.display = 'none'; });
  cv.addEventListener('mousedown', function (e) { var r = cv.getBoundingClientRect(); select(pick(e.clientX - r.left, e.clientY - r.top)); });
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target.closest('[data-pid],[data-tab],#o-kill') : null;
    if (!t) return;
    if (t.hasAttribute('data-tab')) { tab = t.getAttribute('data-tab'); renderSide(); return; }
    if (t.id === 'o-kill') {
      var p = procs[selected];
      if (p) { ghosts.push({ x: p.px, y: p.py, t: performance.now(), c: COLORS.red }); window.swSend('kill', { pid: String(selected) }); }
      return;
    }
    select(Number(t.getAttribute('data-pid')));
  });

  /* ---------- draw ---------- */
  function draw(now) {
    requestAnimationFrame(draw);
    if (now - fpsT > 1000) { fps = framesN; framesN = 0; fpsT = now; var f = $('o-fps'); if (f) f.textContent = fps; }
    tickStats();
    if (W < 50) return;
    g.clearRect(0, 0, W, H);
    if (layoutDirty) relayout();
    var key, c, pid, p, i;
    for (key in groups) {
      c = groups[key]; if (c.x === undefined) continue;
      c.x += (c.sx - c.x) * 0.1; c.y += (c.sy - c.y) * 0.1; c.z += (c.sc - c.z) * 0.1;
      var rr = Math.max(4, c.r * c.z), breathe = 1 + Math.sin(now / 1800 + c.key) * 0.004;
      g.strokeStyle = 'rgba(255,255,255,0.07)'; g.lineWidth = 1;
      g.beginPath(); g.arc(c.x, c.y, rr * breathe, 0, 6.2832); g.stroke();
      g.font = '500 11px ui-sans-serif,-apple-system,"SF Pro Text",Inter,sans-serif'; g.textAlign = 'left';
      var wl = g.measureText(c.label).width, wn = g.measureText(String(c.n)).width, tw = wl + wn + 26;
      var lx = c.x - tw / 2, ly = c.y - rr - 27;
      g.fillStyle = 'rgba(14,14,16,0.94)'; roundRect(lx, ly, tw, 20, 10); g.fill();
      g.strokeStyle = 'rgba(255,255,255,0.11)'; g.lineWidth = 1; roundRect(lx, ly, tw, 20, 10); g.stroke();
      g.fillStyle = '#a1a1a6'; g.fillText(c.label, lx + 10, ly + 14);
      g.fillStyle = '#ededed'; g.fillText(String(c.n), lx + 10 + wl + 6, ly + 14);
    }
    /* dots */
    g.globalCompositeOperation = 'lighter';
    for (pid in procs) {
      p = procs[pid]; c = groups[p.parent]; if (!c || p.slot < 0 || c.x === undefined) continue;
      var sp = slotPos(p.slot), tx = c.x + sp[0] * c.z, ty = c.y + sp[1] * c.z;
      if (p.px === undefined) { p.px = tx; p.py = ty; }
      p.px += (tx - p.px) * 0.18; p.py += (ty - p.py) * 0.18;
      var age = (now - p.born) / 520, pop = age >= 1 ? 1 : Math.max(0, back(age));
      var rad = Math.max(2, Math.min(6.5, 1.6 + Math.log(1 + p.mem) * 0.42)) * Math.min(1.5, Math.max(0.6, c.z * 0.9)) * pop;
      var base = p.status === 1 ? COLORS.run : p.status === 2 ? COLORS.runnable : COLORS.wait;
      var a = 0.5 + p.heat * 0.5;
      if (p.heat > 0.3) {
        var gr = g.createRadialGradient(p.px, p.py, 0, p.px, p.py, rad * 4.5);
        gr.addColorStop(0, rgba(COLORS.run, p.heat * 0.35)); gr.addColorStop(1, rgba(COLORS.run, 0));
        g.fillStyle = gr; g.fillRect(p.px - rad * 4.5, p.py - rad * 4.5, rad * 9, rad * 9);
      }
      g.fillStyle = rgba(base, a); g.beginPath(); g.arc(p.px, p.py, Math.max(0.1, rad + p.heat * 1.4), 0, 6.2832); g.fill();
    }
    g.globalCompositeOperation = 'source-over';
    /* backlog rings */
    for (pid in procs) {
      p = procs[pid]; if (p.mail < 8 || p.px === undefined) continue;
      var lvl = Math.min(1, Math.log(1 + p.mail) / Math.log(5000));
      g.strokeStyle = rgba(COLORS.red, 0.4 + lvl * 0.6); g.lineWidth = 1 + lvl * 2;
      g.beginPath(); g.arc(p.px, p.py, Math.max(2, 5 + lvl * 13 + Math.sin(now / 220 + p.pid) * lvl * 1.8), 0, 6.2832); g.stroke();
    }
    /* selection: parent and child links */
    var sel = procs[selected];
    if (sel && sel.px !== undefined) {
      var par = procs[sel.parent];
      g.lineWidth = 1;
      if (par && par.px !== undefined) { g.strokeStyle = 'rgba(255,255,255,0.5)'; g.beginPath(); g.moveTo(sel.px, sel.py); g.lineTo(par.px, par.py); g.stroke(); }
      g.strokeStyle = 'rgba(59,158,255,0.2)';
      for (pid in procs) { p = procs[pid]; if (p.parent === sel.pid && p.px !== undefined) { g.beginPath(); g.moveTo(sel.px, sel.py); g.lineTo(p.px, p.py); g.stroke(); } }
      g.strokeStyle = '#fff'; g.lineWidth = 1.5; g.beginPath(); g.arc(sel.px, sel.py, 10 + Math.sin(now / 300) * 1, 0, 6.2832); g.stroke();
    }
    var hp = procs[hover];
    if (hp && hp.px !== undefined && hover !== selected) { g.strokeStyle = 'rgba(255,255,255,0.7)'; g.lineWidth = 1; g.beginPath(); g.arc(hp.px, hp.py, 9, 0, 6.2832); g.stroke(); }
    /* exits fade out; spawns get a soft ring */
    for (i = ghosts.length - 1; i >= 0; i--) {
      var gh = ghosts[i], t = (now - gh.t) / 800;
      if (t >= 1 || gh.x === undefined) { ghosts.splice(i, 1); continue; }
      g.strokeStyle = rgba(gh.c, (1 - t) * 0.9); g.lineWidth = 1.5 * (1 - t) + 0.3;
      g.beginPath(); g.arc(gh.x, gh.y, Math.max(0.1, 3 + 26 * ease(t)), 0, 6.2832); g.stroke();
      g.fillStyle = rgba(gh.c, (1 - t) * 0.5); g.beginPath(); g.arc(gh.x, gh.y, Math.max(0.1, 4 * (1 - t)), 0, 6.2832); g.fill();
    }
    for (i = pops.length - 1; i >= 0; i--) {
      var po = pops[i], tp = (now - po.born) / 900;
      if (tp >= 1) { pops.splice(i, 1); continue; }
      if (po.px === undefined) continue;
      g.strokeStyle = rgba(COLORS.green, (1 - tp) * 0.8); g.lineWidth = 1.5 * (1 - tp) + 0.3;
      g.beginPath(); g.arc(po.px, po.py, Math.max(0.1, 2 + 22 * ease(tp)), 0, 6.2832); g.stroke();
    }
  }
  function roundRect(x, y, w, h, r) {
    g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r);
    g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();
  }
  window.__swObserver = { procs: procs, groups: groups };
  requestAnimationFrame(draw);
})();
