module Main

# swarm-live — Swarm Arena
#
#   make bin/arena && ./bin/arena      ->  http://localhost:4007
#
# 600 real swarmrt processes, one per cell, all supervised. Every agent
# pings other agents; cell brightness is how many pings it just received.
# Click a cell (or hit "kill 10%") and that process gets a 'killed' exit
# signal — the dynamic supervisor restarts it and the cell flashes orange.
# The stats are the runtime's own swarm_stats(). Updates reach the browser
# as batched stream upserts (only the cells that changed).

import LiveView

let n_agents = 600
let tick_ms = 200

# ------------------------------------------------------------
# Agents
# ------------------------------------------------------------
fun agent(i, tab) {
    ets_put(tab, i, self())
    ets_update_counter(tab, "g/" ++ to_string(i), 1, 0)
    agent_loop(i, tab, 0)
}

# Drain pings first (after 0 fires only on an empty mailbox), then send
# this round's burst and nap. A pending 'killed' signal lands any time.
fun agent_loop(i, tab, round) {
    receive {
        {'ping'} ->
            ets_update_counter(tab, "r/" ++ to_string(i), 1, 0)
            agent_loop(i, tab, round)
        _o ->
            agent_loop(i, tab, round)
        after 0 {
            fire(i, tab, round, num(ets_get(tab, 'burst')))
            sleep(100)
            agent_loop(i, tab, round + 1)
        }
    }
}

fun fire(i, tab, round, k) {
    if (k <= 0) { 'ok' }
    else {
        # product of two index hashes / n skews traffic toward low indices,
        # so a few agents are hubs and the grid shows a heat gradient
        a = (i * 17 + k * 131 + round * 7) % n_agents
        b = (i * 29 + k * 53 + round * 13) % n_agents
        peer = ets_get(tab, a * b / n_agents)
        if (peer == nil) { 'skip' } else { send(peer, {'ping'}) }
        fire(i, tab, round, k - 1)
    }
}

fun num(x) { if (x == nil) { 0 } else { x } }

fun spawn_agents(sup, tab, i) {
    if (i >= n_agents) { 'ok' }
    else {
        sup_start_child(sup, {nil, fun() { agent(i, tab) }, 'permanent'})
        spawn_agents(sup, tab, i + 1)
    }
}

# ------------------------------------------------------------
# Arena — samples the table every tick, broadcasts only what changed
# ------------------------------------------------------------
fun bucket(d) {
    if (d <= 0) { 0 } else { if (d <= 5) { 1 } else { if (d <= 25) { 2 } else { if (d <= 100) { 3 } else { 4 } } } }
}

fun cell_html(i, b, revived) {
    cls = if (revived == 'true') { "c l" ++ to_string(b) ++ " rv" } else { "c l" ++ to_string(b) }
    "<i sw-key=\"" ++ to_string(i) ++ "\" class=\"" ++ cls ++ "\"></i>"
}

fun tick_cells(tab, i, acc, sum) {
    if (i >= n_agents) { {acc, sum} }
    else {
        si = to_string(i)
        r = num(ets_get(tab, "r/" ++ si))
        pr = num(ets_get(tab, "pr/" ++ si))
        g = num(ets_get(tab, "g/" ++ si))
        pg = num(ets_get(tab, "pg/" ++ si))
        pb = num(ets_get(tab, "pb/" ++ si))
        b = bucket(r - pr)
        ets_put(tab, "pr/" ++ si, r)
        ets_put(tab, "pg/" ++ si, g)
        ets_put(tab, "pb/" ++ si, b)
        revived = if (g > pg && pg > 0) { 'true' } else { 'false' }
        if (b != pb || revived == 'true') {
            tick_cells(tab, i + 1, [cell_html(i, b, revived) | acc], sum + (r - pr))
        } else {
            tick_cells(tab, i + 1, acc, sum + (r - pr))
        }
    }
}

fun snapshot(tab, i, acc) {
    if (i >= n_agents) { acc }
    else {
        si = to_string(i)
        snapshot(tab, i + 1, [cell_html(i, num(ets_get(tab, "pb/" ++ si)), 'false') | acc])
    }
}

fun kill_one(tab, i) {
    pid = ets_get(tab, i)
    if (pid == nil) { 'noop' } else { exit_proc(pid, 'killed') }
}

fun kill_random(tab, k) {
    if (k <= 0) { 'ok' }
    else {
        c = ets_update_counter(tab, 'rng', 1, 0)
        kill_one(tab, (c * 7919 + 13) % n_agents)
        kill_random(tab, k - 1)
    }
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
        {'snap', pid} ->
            send(pid, {'cells', snapshot(tab, 0, [])})
            arena_loop(tab)
        after tick_ms {
            res = tick_cells(tab, 0, [], 0)
            st = swarm_stats()
            LiveView.broadcast("arena", {'tick', elem(res, 0), elem(res, 1) * 1000 / tick_ms,
                map_get(st, 'processes'), map_get(st, 'crashes'),
                map_get(st, 'restarts'), map_get(st, 'mailbox_dropped')})
            arena_loop(tab)
        }
    }
}

fun arena_send(msg) {
    a = whereis('arena')
    if (a == nil) { 'noop' } else { send(a, msg) }
}

# ------------------------------------------------------------
# View
# ------------------------------------------------------------
fun mount(params) {
    if (LiveView.connected(params) == 'true') {
        LiveView.subscribe("arena")
        arena_send({'snap', self()})
    } else {
        'noop'
    }
    %{procs: 0, crashes: 0, restarts: 0, rate: 0, drops: 0}
}

fun stat(label, dyn) {
    "<div class=\"st\"><b>" ++ dyn ++ "</b><span>" ++ label ++ "</span></div>"
}

fun render(assigns) {
    LiveView.h(
        "<style>" ++
        "body{margin:0;background:#0a0a0a}" ++
        ".arena{max-width:980px;margin:0 auto;padding:1.5rem 1rem;font-family:sans-serif;color:#e6e6e6}" ++
        ".arena h1{font-size:1.25rem;font-weight:600;margin:0 0 .25rem}" ++
        ".arena p{color:#888;font-size:.85rem;margin:0 0 1rem}" ++
        ".stats{display:flex;gap:1.5rem;flex-wrap:wrap;margin-bottom:1rem}" ++
        ".st{display:flex;flex-direction:column}.st b{font-size:1.5rem;font-variant-numeric:tabular-nums}" ++
        ".st span{font-size:.7rem;color:#777;text-transform:uppercase;letter-spacing:.06em}" ++
        ".bar{display:flex;gap:.5rem;margin-bottom:1rem;flex-wrap:wrap}" ++
        "#grid{display:grid;grid-template-columns:repeat(30,1fr);gap:2px}" ++
        ".c{aspect-ratio:1;border-radius:2px;background:#151515;cursor:pointer;display:block}" ++
        ".c:hover{outline:1px solid #888}" ++
        ".l1{background:#12303a}.l2{background:#14586b}.l3{background:#1493a8}.l4{background:#4fd1e8}" ++
        ".rv{animation:rv 1.2s ease-out}" ++
        "@keyframes rv{0%{background:#f97316;transform:scale(1.8)}100%{transform:scale(1)}}" ++
        "</style>" ++
        "<div class=\"arena\"><h1>Swarm Arena</h1>" ++
        "<p>600 live swarmrt processes under one supervisor. Click a cell to kill it &mdash; watch it come back.</p>" ++
        "<div class=\"stats\">" ++
        stat("processes", "{{}}") ++ stat("msgs / sec", "{{}}") ++
        stat("crashes", "{{}}") ++ stat("restarts", "{{}}") ++ stat("mailbox drops", "{{}}") ++
        "</div>" ++
        "<div class=\"bar\">" ++
        "<button sw-click=\"burst\" sw-value-n=\"1\">calm</button>" ++
        "<button sw-click=\"burst\" sw-value-n=\"5\">busy</button>" ++
        "<button sw-click=\"burst\" sw-value-n=\"20\">storm</button>" ++
        "<button sw-click=\"chaos\" sw-value-k=\"60\" style=\"margin-left:auto\">kill 10%</button>" ++
        "</div>" ++
        "<div id=\"grid\" sw-stream sw-click-key=\"kill\"></div></div>",
        [map_get(assigns, 'procs'), map_get(assigns, 'rate'),
         map_get(assigns, 'crashes'), map_get(assigns, 'restarts'),
         map_get(assigns, 'drops')])
}

fun handle_event(name, value, assigns) {
    if (name == "kill") {
        arena_send({'kill', to_int(map_get(value, 'key'))})
        assigns
    } else { if (name == "burst") {
        arena_send({'burst', to_int(map_get(value, 'n'))})
        assigns
    } else { if (name == "chaos") {
        arena_send({'kill_random', to_int(map_get(value, 'k'))})
        assigns
    } else {
        assigns
    }}}
}

fun handle_info(msg, assigns) {
    tag = elem(msg, 0)
    if (tag == 'tick') {
        htmls = elem(msg, 1)
        if (length(htmls) > 0) {
            LiveView.stream_op(assigns, %{t: "s", id: "grid", op: "upsert", htmls: htmls})
        } else { 'noop' }
        a1 = LiveView.assign(assigns, 'rate', elem(msg, 2))
        a2 = LiveView.assign(a1, 'procs', elem(msg, 3))
        a3 = LiveView.assign(a2, 'crashes', elem(msg, 4))
        a4 = LiveView.assign(a3, 'restarts', elem(msg, 5))
        LiveView.assign(a4, 'drops', elem(msg, 6))
    } else { if (tag == 'cells') {
        LiveView.stream_op(assigns, %{t: "s", id: "grid", op: "upsert", htmls: elem(msg, 1)})
        assigns
    } else {
        assigns
    }}
}

fun main() {
    tab = ets_new()
    ets_put(tab, 'burst', 5)
    sup = dyn_supervisor(1000000, 1)
    spawn_agents(sup, tab, 0)
    register('arena', spawn(arena_loop(tab)))
    LiveView.start(4007, %{
        title: "Swarm Arena",
        mount: mount,
        render: render,
        handle_event: handle_event,
        handle_info: handle_info
    })
}
