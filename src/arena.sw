module Main

# swarm-live — Swarm Arena
#
#   make bin/arena && ./bin/arena      ->  http://localhost:4007
#
# 600 real swarmrt processes under one dynamic supervisor. A driver ticks
# every agent every 100ms; each tick an agent sends `burst` pings to other
# agents. Every ~100ms the arena samples the real counters (pings received,
# restart generations, last peer, kill/start timestamps) and ws_sends ONE
# compact frame to each viewer; src/arena.js draws it on a canvas:
#   heat    = pings each agent just received
#   comets  = real recent agent -> agent messages
#   kills   = exit_proc(pid, 'killed') -> shockwave, supervisor beam
#   respawn = the supervisor's restart (generation counter bumped), with the
#             measured kill -> restart time
# Nothing on screen is simulated.

import LiveView
import ArenaJs
import Std

let n_agents = 600
let tick_ms = 100

# ETS key space: the pid lives at i; every other per-agent value is a band
# of n_agents ints above it. Ints, not strings — agents touch these hundreds
# of thousands of times a second.
let k_gen = 1000
let k_recv = 2000
let k_prev_recv = 3000
let k_prev_gen = 4000
let k_prev_bucket = 5000
let k_last_peer = 7000
let k_start_ts = 8000
let k_kill_ts = 9000

# ------------------------------------------------------------
# Agents
# ------------------------------------------------------------
fun agent(i, tab) {
    ets_put(tab, i, self())
    ets_put(tab, k_start_ts + i, timestamp())
    ets_update_counter(tab, k_gen + i, 1, 0)
    agent_loop(i, tab, 0)
}

# Pings only COUNT. Sending is driven by the driver's {'tick'} so the rate
# is exactly burst x agents x 10/s — if a ping could trigger sends, every
# message would spawn k more and the swarm would saturate itself.
fun agent_loop(i, tab, round) {
    receive {
        {'ping'} ->
            ets_update_counter(tab, k_recv + i, 1, 0)
            agent_loop(i, tab, round)
        {'tick'} ->
            fire(i, tab, round, num(ets_get(tab, 'burst')))
            agent_loop(i, tab, round + 1)
        _o ->
            agent_loop(i, tab, round)
    }
}

fun fire(i, tab, round, k) {
    if (k <= 0) { 'ok' }
    else {
        # product of two index hashes / n skews traffic toward low indices,
        # so a few agents are hubs and the grid shows a heat gradient
        a = (i * 17 + k * 131 + round * 7) % n_agents
        b = (i * 29 + k * 53 + round * 13) % n_agents
        p = a * b / n_agents
        ets_put(tab, k_last_peer + i, p)
        peer = ets_get(tab, p)
        if (peer == nil) { 'skip' } else { send(peer, {'ping'}) }
        fire(i, tab, round, k - 1)
    }
}

fun num(x) { if (x == nil) { 0 } else { x } }

# One driver ticks every agent every 100ms (looks pids up fresh, so a
# restarted agent is picked up on the very next tick).
fun driver_loop(tab) {
    tick_agents(tab, 0)
    sleep(tick_ms)
    driver_loop(tab)
}

fun tick_agents(tab, i) {
    if (i >= n_agents) { 'ok' }
    else {
        pid = ets_get(tab, i)
        if (pid == nil) { 'skip' } else { send(pid, {'tick'}) }
        tick_agents(tab, i + 1)
    }
}

fun spawn_agents(sup, tab, i) {
    if (i >= n_agents) { 'ok' }
    else {
        sup_start_child(sup, {nil, fun() { agent(i, tab) }, 'permanent'})
        spawn_agents(sup, tab, i + 1)
    }
}

# ------------------------------------------------------------
# Arena — samples the table every tick, broadcasts one frame
# ------------------------------------------------------------
fun bucket(d0) {
    d = d0 * 100 / tick_ms
    if (d <= 0) { 0 } else { if (d <= 2) { 1 } else { if (d <= 6) { 2 } else { if (d <= 20) { 3 } else { 4 } } } }
}

# Walk agents high -> low so consing builds heat[] in ascending order.
# Collects respawn events (generation bumped) and the total pings received.
fun sample(tab, i, heat, evs, sum) {
    if (i < 0) { {heat, evs, sum} }
    else {
        r = num(ets_get(tab, k_recv + i))
        pr = num(ets_get(tab, k_prev_recv + i))
        g = num(ets_get(tab, k_gen + i))
        pg = num(ets_get(tab, k_prev_gen + i))
        b = bucket(r - pr)
        ets_put(tab, k_prev_recv + i, r)
        ets_put(tab, k_prev_gen + i, g)
        if (g > pg && pg > 0) {
            ms = num(ets_get(tab, k_start_ts + i)) - num(ets_get(tab, k_kill_ts + i))
            ev = ['u', i, to_string(ets_get(tab, i)), ms, g]
            sample(tab, i - 1, [b | heat], [ev | evs], sum + (r - pr))
        } else {
            sample(tab, i - 1, [b | heat], evs, sum + (r - pr))
        }
    }
}

# Every 5th agent's most recent real destination: [[from, to], ...]
fun edges(tab, i, acc) {
    if (i < 0) { acc }
    else {
        p = ets_get(tab, k_last_peer + i)
        if (p == nil) { edges(tab, i - 5, acc) } else { edges(tab, i - 5, [[i, p] | acc]) }
    }
}

fun kill_one(tab, i) {
    pid = ets_get(tab, i)
    if (pid == nil) { 'noop' } else {
        ets_put(tab, k_kill_ts + i, timestamp())
        ets_put(tab, 'evq', [['k', i, to_string(pid)] | num_list(ets_get(tab, 'evq'))])
        exit_proc(pid, 'killed')
    }
}

fun num_list(x) { if (x == nil) { [] } else { x } }

fun kill_random(tab, k) {
    if (k <= 0) { 'ok' }
    else {
        c = ets_update_counter(tab, 'rng', 1, 0)
        kill_one(tab, (c * 7919 + 13) % n_agents)
        kill_random(tab, k - 1)
    }
}

fun frame_json(tab) {
    res = sample(tab, n_agents - 1, [], [], 0)
    kills = num_list(ets_get(tab, 'evq'))
    ets_put(tab, 'evq', [])
    total = ets_update_counter(tab, 'total', elem(res, 2), 0)
    st = swarm_stats()
    json_encode(%{t: "ev", n: "frame", d: %{
        h: elem(res, 0),
        e: edges(tab, n_agents - 1, []),
        ev: Std.reverse(kills) ++ elem(res, 1),
        p: map_get(st, 'processes'),
        c: map_get(st, 'crashes'),
        r: map_get(st, 'restarts'),
        m: elem(res, 2) * 1000 / tick_ms,
        tot: total,
        b: num(ets_get(tab, 'burst'))
    }})
}

fun arena_loop(tab) {
    receive {
        {'kill', i} ->
            kill_one(tab, i)
            arena_loop(tab)
        {'kill_random', k} ->
            kill_random(tab, k)
            arena_loop(tab)
        {'burst', b} ->
            ets_put(tab, 'burst', b)
            arena_loop(tab)
        after tick_ms {
            LiveView.broadcast("arena", {'frame', frame_json(tab)})
            arena_loop(tab)
        }
    }
}

fun arena_send(msg) {
    a = whereis('arena')
    if (a == nil) { 'noop' } else { send(a, msg) }
}

# ------------------------------------------------------------
# View — a static shell; all motion is in arena.js
# ------------------------------------------------------------
fun mount(params) {
    if (LiveView.connected(params) == 'true') {
        LiveView.subscribe("arena")
    } else {
        'noop'
    }
    %{}
}

fun stat(id, label) {
    "<div class=\"st\"><b id=\"" ++ id ++ "\">-</b><span>" ++ label ++ "</span></div>"
}

fun render(assigns) {
    LiveView.h(
        "<style>" ++
        "html,body{height:100%;overflow:hidden;background:#07080a}" ++
        "#stage{position:fixed;inset:0;width:100vw;height:100vh;display:block}" ++
        ".hud{position:fixed;top:14px;left:20px;font-family:-apple-system,sans-serif;color:#e6e6e6;pointer-events:none}" ++
        ".hud h1{font-size:1.1rem;font-weight:600;letter-spacing:.02em}" ++
        ".hud p{font-size:.78rem;color:#7d8590;margin-top:2px}" ++
        ".side{position:fixed;top:14px;right:16px;width:300px;font-family:-apple-system,sans-serif;color:#e6e6e6}" ++
        ".stats{display:grid;grid-template-columns:1fr 1fr;gap:10px 14px;background:rgba(18,20,24,.82);" ++
        "border:1px solid #23272e;border-radius:12px;padding:12px 14px;backdrop-filter:blur(6px)}" ++
        ".st b{display:block;font-size:1.35rem;font-variant-numeric:tabular-nums;font-weight:600}" ++
        ".st span{font-size:.62rem;color:#7d8590;text-transform:uppercase;letter-spacing:.08em}" ++
        ".bar{display:flex;gap:6px;margin:10px 0;flex-wrap:wrap}" ++
        ".btn{font:inherit;font-size:.8rem;font-weight:500;color:#e6e6e6;background:#14161a;" ++
        "border:1px solid #2a2f37;border-radius:8px;padding:.45rem .85rem;cursor:pointer;" ++
        "transition:background .08s,border-color .08s,transform .05s}" ++
        ".btn:hover{background:#1d2026;border-color:#3d434d}.btn:active{transform:scale(.95)}" ++
        ".btn.on{background:#e6e6e6;color:#07080a;border-color:#e6e6e6}" ++
        ".btn.danger{background:#2a0f0a;border-color:#7c2d12;color:#fdba74}" ++
        ".btn.danger:hover{background:#3b140c;border-color:#f97316}" ++
        ".btn.nuke{background:#3b0d0d;border-color:#b91c1c;color:#fecaca;font-weight:600}" ++
        ".btn.nuke:hover{background:#561010;border-color:#ef4444}" ++
        "#log{background:rgba(12,13,16,.82);border:1px solid #23272e;border-radius:12px;padding:8px 10px;" ++
        "font:11px/1.55 ui-monospace,Menlo,monospace;height:260px;overflow:hidden}" ++
        ".ln.k{color:#ff7b6b}.ln.u{color:#6ee7a8}.ln.m{color:#7d8590}" ++
        "</style>" ++
        "<canvas id=\"stage\" sw-keep></canvas>" ++
        "<div class=\"hud\"><h1>Swarm Arena</h1>" ++
        "<p>600 real swarmrt processes under one supervisor. Click a cell to kill it.</p></div>" ++
        "<div class=\"side\"><div class=\"stats\">" ++
        stat("s-proc", "processes") ++ stat("s-msgs", "msgs / sec") ++
        stat("s-tot", "total msgs") ++ stat("s-ms", "avg respawn") ++
        stat("s-crash", "crashes") ++ stat("s-rest", "restarts") ++
        "</div><div class=\"bar\">" ++
        "<button class=\"btn\" data-burst=\"1\">calm</button>" ++
        "<button class=\"btn\" data-burst=\"5\">busy</button>" ++
        "<button class=\"btn\" data-burst=\"20\">storm</button>" ++
        "<button class=\"btn danger\" data-kill=\"60\" style=\"margin-left:auto\">kill 10%</button>" ++
        "<button class=\"btn nuke\" data-kill=\"300\">kill 50%</button></div>" ++
        "<div id=\"log\" sw-keep></div></div>",
        [])
}

fun handle_event(name, value, assigns) {
    if (name == "kill") {
        arena_send({'kill', to_int(map_get(value, 'key'))})
    } else { if (name == "burst") {
        arena_send({'burst', to_int(map_get(value, 'n'))})
    } else { if (name == "chaos") {
        arena_send({'kill_random', to_int(map_get(value, 'k'))})
    } else {
        'noop'
    }}}
    assigns
}

# A frame is already a finished JSON string — straight to the socket.
fun handle_info(msg, assigns) {
    if (elem(msg, 0) == 'frame') {
        conn = map_get(assigns, '_conn')
        if (conn == nil) { 'noop' } else { ws_send(conn, elem(msg, 1)) }
    } else { 'noop' }
    assigns
}

fun main() {
    tab = ets_new()
    ets_put(tab, 'burst', 5)
    sup = dyn_supervisor(1000000, 1)
    spawn_agents(sup, tab, 0)
    spawn(driver_loop(tab))
    register('arena', spawn(arena_loop(tab)))
    LiveView.start(4007, %{
        title: "Swarm Arena",
        js: ArenaJs.js(),
        mount: mount,
        render: render,
        handle_event: handle_event,
        handle_info: handle_info
    })
}
