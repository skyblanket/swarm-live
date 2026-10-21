module Observer

# Swarm Observer — a live X-ray of the swarmrt node it runs inside.
#
# Mount it in ANY swarm-live app as a second route:
#
#     import Observer
#     LiveView.start(4000, [{"/", my_view}, {"/_observer", Observer.view(%{})}])
#
# `Observer.view(%{kill: 'true'})` also lets the UI kill a process (off by
# default: the observer is read-only unless you opt in).
#
# A sampler process wakes 4x/s (only while somebody is watching) and reads
# the runtime's own introspection — process_list / process_info /
# swarm_stats — then ws_sends one compact frame per viewer. src/observer.js
# lays the processes out as clusters by supervisor and draws them.
#   dot size   = process memory          red ring  = mailbox backlog
#   dot colour = status                  brightness = message rate
#   spawn / exit rings, per-scheduler load and top-N lists are all sampled.
# Nothing is simulated.

import LiveView
import ObserverJs

export [view, ensure]

fun num(x) { if (x == nil) { 0 } else { x } }
fun nonneg(x) { if (x < 0) { 0 } else { x } }

# ------------------------------------------------------------
# Sampler
# ------------------------------------------------------------
# Idempotent: starts the sampler once per node.
fun ensure(kill) {
    if (whereis('observer_sampler') == nil) {
        register('observer_sampler', spawn(sampler_start(kill)))
    } else { 'ok' }
}

fun sampler_start(kill) {
    LiveView.subscribe("observer_presence")
    # started lazily by a viewer's mount, so assume one viewer until a presence
    # message says otherwise
    sampler_loop(kill, map_new(), [], [0, 0, 0, 0], 1, 0)
}

fun sampler_loop(kill, prev, psch, pst, viewers, tick) {
    receive {
        {'presence', _t, n} ->
            sampler_loop(kill, prev, psch, pst, n, tick)
        {'kill', n} ->
            if (kill == 'true') { kill_pid(process_list(), n) } else { 'denied' }
            sampler_loop(kill, prev, psch, pst, viewers, tick)
        _o ->
            sampler_loop(kill, prev, psch, pst, viewers, tick)
        after 250 {
            if (viewers <= 0) {
                sampler_loop(kill, prev, psch, pst, viewers, tick)
            } else {
                st = swarm_stats()
                cur = [num(map_get(st, 'spawns')), num(map_get(st, 'crashes')),
                       num(map_get(st, 'restarts')), num(map_get(st, 'mailbox_dropped'))]
                schs = list_or_empty(map_get(st, 'scheduler_stats'))
                res = rows(process_list(), prev, [], map_new())
                LiveView.broadcast("observer", {'obs', json_encode(%{t: "ev", n: "obs", d: %{
                    n: num(map_get(st, 'processes')),
                    sc: num(map_get(st, 'schedulers')),
                    sch: sch_frame(schs, psch, 0, []),
                    tot: cur,
                    dl: deltas(cur, pst, 0, []),
                    p: elem(res, 0),
                    k: if (kill == 'true') { 1 } else { 0 }
                }})})
                sampler_loop(kill, elem(res, 1), sch_now(schs, []), cur, viewers, tick + 1)
            }
        }
    }
}

fun list_or_empty(x) { if (x == nil) { [] } else { x } }

fun kill_pid(pids, n) {
    if (length(pids) == 0) { 'none' }
    else {
        i = process_info(hd(pids))
        if (i != nil && map_get(i, 'pid') == n) { exit_proc(hd(pids), 'killed') }
        else { kill_pid(tl(pids), n) }
    }
}

# one row per process: [pid, parent, status, mailbox, memKB, recv delta, sent delta, name|0]
fun rows(pids, prev, acc, np) {
    if (length(pids) == 0) { {acc, np} }
    else {
        i = process_info(hd(pids))
        if (i == nil) { rows(tl(pids), prev, acc, np) }
        else {
            pid = map_get(i, 'pid')
            recv = num(map_get(i, 'messages_recv'))
            sent = num(map_get(i, 'messages_sent'))
            old = map_get(prev, pid)
            dr = if (old == nil) { 0 } else { nonneg(recv - hd(old)) }
            ds = if (old == nil) { 0 } else { nonneg(sent - hd(tl(old))) }
            s = map_get(i, 'status')
            code = if (s == 'waiting') { 0 } else { if (s == 'running') { 1 } else { 2 } }
            nm = map_get(i, 'name')
            name = if (nm == nil || nm == "nil") { 0 } else { nm }
            rows(tl(pids), prev,
                [[pid, num(map_get(i, 'parent')), code, num(map_get(i, 'mailbox_len')),
                  num(map_get(i, 'memory')) / 1024, dr, ds, name] | acc],
                map_put(np, pid, [recv, sent]))
        }
    }
}

# scheduler snapshot as [[run, steals, idle_waits], ...] for next frame's deltas
fun sch_now(schs, acc) {
    if (length(schs) == 0) { acc }
    else {
        s = hd(schs)
        sch_now(tl(schs), list_append(acc, [num(map_get(s, 'procs_run')), num(map_get(s, 'steals')),
                                            num(map_get(s, 'idle_waits'))]))
    }
}

fun nth_or(lst, k, dflt) {
    if (length(lst) == 0) { dflt } else { if (k <= 0) { hd(lst) } else { nth_or(tl(lst), k - 1, dflt) } }
}

# [[id, run delta, steal delta, idle delta], ...]
fun sch_frame(schs, psch, k, acc) {
    if (length(schs) == 0) { acc }
    else {
        s = hd(schs)
        run = num(map_get(s, 'procs_run'))
        st = num(map_get(s, 'steals'))
        idle = num(map_get(s, 'idle_waits'))
        p = nth_or(psch, k, [run, st, idle])
        sch_frame(tl(schs), psch, k + 1,
            list_append(acc, [k, nonneg(run - hd(p)), nonneg(st - hd(tl(p))), nonneg(idle - hd(tl(tl(p))))]))
    }
}

fun deltas(cur, prev, k, acc) {
    if (k >= length(cur)) { acc }
    else {
        deltas(cur, prev, k + 1, list_append(acc, nonneg(nth_or(cur, k, 0) - nth_or(prev, k, 0))))
    }
}

# ------------------------------------------------------------
# View
# ------------------------------------------------------------
fun view(opts) {
    kill = map_get(opts, 'kill', 'false')
    %{
        title: "Swarm Observer",
        js: ObserverJs.js(),
        mount: fun(params) { mount(kill, params) },
        render: fun(assigns) { render(assigns) },
        handle_event: fun(name, value, assigns) { handle_event(name, value, assigns) },
        handle_info: fun(msg, assigns) { handle_info(msg, assigns) }
    }
}

fun mount(kill, params) {
    if (LiveView.connected(params) == 'true') {
        ensure(kill)
        LiveView.subscribe("observer")
        LiveView.subscribe("observer_presence")
        LiveView.presence_track("observer_presence")
    } else {
        'noop'
    }
    %{}
}

fun stat(id, label) {
    "<div class=\"card stat\"><div class=\"lbl\">" ++ label ++ "</div><div class=\"val\" id=\"v-" ++ id ++ "\">&ndash;</div>" ++
    "<div class=\"chip\" id=\"d-" ++ id ++ "\"></div><canvas id=\"sp-" ++ id ++ "\" class=\"sp\" sw-keep></canvas></div>"
}

fun css() {
    "<style>" ++
    ":root{--bg:#000;--card:#0a0a0a;--line:#1f1f1f;--line2:#2e2e2e;--tx:#ededed;--mu:#8f8f8f;--blue:#3b9eff;--red:#ff4d4d;--amber:#f5a623;--green:#50e3c2}" ++
    "*{box-sizing:border-box}html,body{height:100%;background:var(--bg);color:var(--tx);margin:0}" ++
    "body{font-family:ui-sans-serif,-apple-system,'SF Pro Text',Inter,'Segoe UI',sans-serif;-webkit-font-smoothing:antialiased;overflow:hidden}" ++
    "#live-root{height:100%;display:flex;flex-direction:column}" ++
    ".nav{height:56px;flex:none;display:flex;align-items:center;gap:14px;padding:0 24px;border-bottom:1px solid var(--line);background:rgba(0,0,0,.85);backdrop-filter:blur(8px)}" ++
    ".logo{display:flex;align-items:center;gap:10px;font-weight:600;font-size:14px;letter-spacing:-.01em}" ++
    ".crumb{color:var(--mu);font-size:14px}.crumb:before{content:'/';margin-right:14px;color:#3a3a3a}" ++
    ".live{margin-left:auto;display:flex;align-items:center;gap:8px;font-size:12px;color:var(--mu);padding:5px 11px;border:1px solid var(--line2);border-radius:99px}" ++
    ".dot{width:7px;height:7px;border-radius:50%;background:var(--green);box-shadow:0 0 0 0 rgba(80,227,194,.6);animation:pulse 1.8s infinite}" ++
    "@keyframes pulse{70%{box-shadow:0 0 0 7px rgba(80,227,194,0)}100%{box-shadow:0 0 0 0 rgba(80,227,194,0)}}" ++
    ".main{flex:1;min-height:0;padding:20px 24px 24px;display:flex;flex-direction:column;gap:14px}" ++
    ".cards{display:grid;grid-template-columns:repeat(5,1fr);gap:14px;flex:none}" ++
    ".card{background:var(--card);border:1px solid var(--line);border-radius:12px;transition:border-color .2s}.card:hover{border-color:var(--line2)}" ++
    ".stat{padding:14px 16px 0;position:relative;height:124px;overflow:hidden}" ++
    ".lbl{font-size:12px;color:var(--mu)}.val{font-size:30px;font-weight:600;letter-spacing:-.03em;font-variant-numeric:tabular-nums;margin-top:3px}" ++
    ".chip{font-size:11px;color:var(--mu);margin-top:1px}.chip.up{color:var(--green)}.chip.warn{color:var(--amber)}.chip.bad{color:var(--red)}" ++
    ".sp{position:absolute;left:0;right:0;bottom:0;width:100%;height:34px}" ++
    ".body{flex:1;min-height:0;display:grid;grid-template-columns:1fr 360px;gap:14px}" ++
    ".map{position:relative;overflow:hidden;background-image:radial-gradient(rgba(255,255,255,.07) 1px,transparent 1px);background-size:22px 22px}" ++
    ".map:before{content:'';position:absolute;inset:0;background:radial-gradient(ellipse at center,transparent 40%,rgba(0,0,0,.75));pointer-events:none}" ++
    "#map-cv{position:absolute;inset:0}" ++
    ".mh{position:absolute;top:14px;left:16px;display:flex;align-items:center;gap:10px;pointer-events:none}.mh h2{font-size:13px;font-weight:600;margin:0}" ++
    ".legend{position:absolute;left:16px;bottom:14px;display:flex;gap:14px;font-size:11px;color:var(--mu);pointer-events:none}" ++
    ".legend i{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px}" ++
    ".tip{position:absolute;display:none;pointer-events:none;background:rgba(10,10,10,.96);border:1px solid var(--line2);border-radius:8px;padding:8px 10px;font-size:12px;width:216px;z-index:5}" ++
    ".tip b{display:block;font-size:12px;margin-bottom:2px}.tip span{display:block;color:var(--mu);font-size:11px;line-height:1.5}" ++
    ".col{display:flex;flex-direction:column;gap:14px;min-height:0;overflow:auto;padding-right:2px}" ++
    ".col .card{padding:14px 16px;flex:none}.col h3{font-size:12px;font-weight:600;margin:0 0 10px;display:flex;justify-content:space-between;align-items:center}" ++
    ".seg{display:flex;gap:2px;background:#111;border:1px solid var(--line);border-radius:8px;padding:2px}" ++
    ".seg button{font:inherit;font-size:11px;color:var(--mu);background:transparent;border:0;border-radius:6px;padding:4px 9px;cursor:pointer;transition:all .15s}" ++
    ".seg button:hover{color:var(--tx)}.seg button.on{background:#232323;color:var(--tx)}" ++
    ".li{padding:7px 8px;margin:0 -8px;border-radius:8px;cursor:pointer;transition:background .12s}.li:hover,.li.on{background:#141414}" ++
    ".lt{display:flex;justify-content:space-between;font-size:12px}.lt b{font-weight:500;color:var(--mu);font-variant-numeric:tabular-nums}" ++
    ".bar{height:4px;background:#1a1a1a;border-radius:3px;overflow:hidden;margin:5px 0 3px}.bar i{display:block;height:100%;background:linear-gradient(90deg,#1c5fa8,#3b9eff);border-radius:3px;transition:width .35s ease}" ++
    ".ls{font-size:10.5px;color:#6b6b6b}.empty{font-size:12px;color:var(--mu);padding:6px 0;line-height:1.5}" ++
    ".sc{display:grid;grid-template-columns:22px 1fr 88px;align-items:center;gap:8px;font-size:11px;color:var(--mu);margin-bottom:5px}" ++
    ".sc .bar{margin:0}.sc b{font-weight:500;text-align:right;font-variant-numeric:tabular-nums}" ++
    ".ih{display:flex;justify-content:space-between;align-items:flex-start;gap:8px}.ih h4{margin:0;font-size:14px;font-weight:600}" ++
    ".sub{font-size:11px;color:var(--mu);margin-top:2px}.sub a{color:var(--blue);cursor:pointer}" ++
    ".pill{font-size:11px;padding:2px 9px;border-radius:99px;border:1px solid var(--line2)}" ++
    ".pill.run{color:var(--blue);border-color:rgba(59,158,255,.4)}.pill.runnable{color:var(--amber);border-color:rgba(245,166,35,.4)}" ++
    ".kv{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:12px 0}.kv span{display:block;font-size:10.5px;color:var(--mu)}" ++
    ".kv b{font-size:13px;font-weight:600;font-variant-numeric:tabular-nums}.kv b.bad{color:var(--red)}" ++
    ".sparks2{display:grid;grid-template-columns:1fr 1fr;gap:10px}.sparks2 span{font-size:10.5px;color:var(--mu)}.sparks2 canvas{width:100%;height:34px;display:block}" ++
    ".btn{font:inherit;font-size:12px;font-weight:500;color:var(--tx);background:#111;border:1px solid var(--line2);border-radius:8px;padding:7px 12px;cursor:pointer;margin-top:12px;width:100%;transition:all .15s}" ++
    ".btn.danger{color:#ff8a8a;border-color:#5b2020;background:#1a0b0b}.btn.danger:hover{background:#2a1010;border-color:var(--red)}" ++
    "#o-feed{max-height:210px;overflow:hidden}" ++
    ".ev{display:flex;align-items:center;gap:9px;font-size:12px;padding:5px 0;border-top:1px solid #141414;animation:in .35s ease}.ev:first-child{border-top:0}" ++
    ".ev i{width:6px;height:6px;border-radius:50%;flex:none;background:#555}.ev.spawn i{background:var(--green)}.ev.crash i{background:var(--red)}.ev.exit i{background:#6b6b6b}" ++
    ".ev span{flex:1;color:#cfcfcf;line-height:1.35}.ev b{color:#fff;font-weight:600}.ev em{font-style:normal;color:var(--mu)}.ev time{font-size:10.5px;color:#666;font-variant-numeric:tabular-nums}" ++
    "@keyframes in{from{opacity:0;transform:translateY(-6px)}to{opacity:1;transform:none}}" ++
    "@media(max-width:1080px){.cards{grid-template-columns:repeat(2,1fr)}.body{grid-template-columns:1fr}body{overflow:auto}#live-root{height:auto}.map{height:520px}}" ++
    "</style>"
}

fun render(assigns) {
    LiveView.h(
        css() ++
        "<header class=\"nav\"><div class=\"logo\">" ++
        "<svg width=\"22\" height=\"22\" viewBox=\"0 0 22 22\"><circle cx=\"11\" cy=\"5\" r=\"2.4\" fill=\"#ededed\"/><circle cx=\"5\" cy=\"15\" r=\"2.4\" fill=\"#ededed\"/><circle cx=\"17\" cy=\"15\" r=\"2.4\" fill=\"#ededed\"/><path d=\"M11 5L5 15L17 15Z\" fill=\"none\" stroke=\"#555\" stroke-width=\"1\"/></svg>" ++
        "Swarm Observer</div><span class=\"crumb\">this node</span>" ++
        "<div class=\"live\"><span class=\"dot\"></span>live &middot; <span id=\"o-fps\">0</span> fps &middot; <span id=\"o-view\">1</span> watching</div></header>" ++
        "<div class=\"main\"><div class=\"cards\">" ++
        stat("proc", "Processes") ++ stat("msg", "Messages / s") ++ stat("rs", "Restarts") ++ stat("cr", "Crashes") ++ stat("sch", "Schedulers") ++
        "</div><div class=\"body\">" ++
        "<div class=\"card map\" id=\"map\"><canvas id=\"map-cv\" sw-keep></canvas>" ++
        "<div class=\"mh\"><h2>Process map</h2></div>" ++
        "<div class=\"tip\" id=\"o-tip\" sw-keep></div>" ++
        "<div class=\"legend\"><span><i style=\"background:#3b9eff\"></i>running</span><span><i style=\"background:#f5a623\"></i>runnable</span>" ++
        "<span><i style=\"background:#525a69\"></i>waiting</span><span><i style=\"background:transparent;border:1.5px solid #ff4d4d\"></i>mailbox backlog</span>" ++
        "<span>size = memory</span><span>glow = message rate</span></div></div>" ++
        "<div class=\"col\">" ++
        "<div class=\"card\"><h3>Inspector</h3><div id=\"o-insp\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Needs attention<div class=\"seg\"><button data-tab=\"mail\" class=\"on\">Backlog</button><button data-tab=\"hot\">Busiest</button><button data-tab=\"mem\">Biggest</button></div></h3><div id=\"o-list\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Schedulers</h3><div id=\"o-sch\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Activity</h3><div id=\"o-feed\" sw-keep></div></div>" ++
        "</div></div></div>",
        [])
}

fun handle_event(name, value, assigns) {
    if (name == "kill") {
        s = whereis('observer_sampler')
        if (s == nil) { 'noop' } else { send(s, {'kill', to_int(map_get(value, 'pid'))}) }
    } else { 'noop' }
    assigns
}

# frames are finished JSON strings; presence becomes a viewers event
fun handle_info(msg, assigns) {
    conn = map_get(assigns, '_conn')
    tag = elem(msg, 0)
    if (conn == nil) { 'noop' }
    else { if (tag == 'obs') {
        ws_send(conn, elem(msg, 1))
    } else { if (tag == 'presence') {
        ws_send(conn, json_encode(%{t: "ev", n: "viewers", d: elem(msg, 2)}))
    } else { 'noop' }}}
    assigns
}
