module Main

# swarm-live — Observer demo
#
#   make bin/observer_demo && scripts/run.sh observer_demo   ->  http://localhost:4009
#
# A node with something to look at, all under named supervisors:
#   pipeline  producer -> stage1 -> stage2_slow -> sink. stage2 is slower than
#             the producer during bursts, so its mailbox backs up (red ring)
#             and drains in the calm phase.
#   crashy    24 workers that kill themselves every few seconds; the supervisor
#             restarts them (watch the restart counter and the rings).
#   gossip    150 processes pinging each other (the hot, bright cluster).
#   sleepers  120 processes parked in receive (the dim cluster).
#   fat       3 processes holding a lot of memory.
# The whole UI is `Observer.view`, the same module you can mount in any app.

import LiveView
import Observer

# ---- pipeline ----
fun producer(n) {
    # 10s burst (300/s), 10s calm (40/s)
    burst = (timestamp() / 10000) % 2 == 0
    s1 = whereis('stage1')
    if (s1 != nil) { send(s1, {'job', n}) } else { 'wait' }
    sleep(if (burst) { 3 } else { 25 })
    producer(n + 1)
}

fun stage1() {
    receive {
        {'job', n} ->
            s2 = whereis('stage2_slow')
            if (s2 != nil) { send(s2, {'job', n}) } else { 'drop' }
            stage1()
        _o -> stage1()
    }
}

fun stage2_slow() {
    receive {
        {'job', n} ->
            sleep(4)
            k = whereis('sink')
            if (k != nil) { send(k, {'done', n}) } else { 'drop' }
            stage2_slow()
        _o -> stage2_slow()
    }
}

fun sink(count) {
    receive {
        {'done', _n} -> sink(count + 1)
        _o -> sink(count)
    }
}

# ---- crashy ----
fun crashy(i) {
    sleep(1500 + (i * 977) % 5000)
    exit_proc(self(), 'killed')
    sleep(1000)
}

# ---- gossip ----
fun gossiper(i, tab) {
    ets_put(tab, i, self())
    gossip_loop(i, tab, 0)
}

fun gossip_loop(i, tab, round) {
    receive {
        {'ping'} -> gossip_loop(i, tab, round)
        {'tick'} ->
            p1 = ets_get(tab, (i * 17 + round * 7 + 1) % 150)
            p2 = ets_get(tab, (i * 29 + round * 13 + 5) % 150)
            if (p1 != nil) { send(p1, {'ping'}) } else { 'skip' }
            if (p2 != nil) { send(p2, {'ping'}) } else { 'skip' }
            gossip_loop(i, tab, round + 1)
        _o -> gossip_loop(i, tab, round)
    }
}

fun gossip_driver(tab) {
    tick_all(tab, 0)
    sleep(100)
    gossip_driver(tab)
}

fun tick_all(tab, i) {
    if (i >= 150) { 'ok' }
    else {
        p = ets_get(tab, i)
        if (p != nil) { send(p, {'tick'}) } else { 'skip' }
        tick_all(tab, i + 1)
    }
}

# ---- sleepers / fat ----
fun sleeper() { receive { _o -> sleeper() } }

fun make_list(n, acc) { if (n <= 0) { acc } else { make_list(n - 1, [n, n * 2, n * 3 | acc]) } }

fun hog(n) {
    data = make_list(n, [])
    hog_wait(data)
}
fun hog_wait(data) { receive { _o -> hog_wait(data) } }

# ---- wiring ----
fun start_n(sup, n, mk) {
    if (n <= 0) { 'ok' }
    else { sup_start_child(sup, {nil, mk(n), 'permanent'})  start_n(sup, n - 1, mk) }
}

fun main() {
    pl = dyn_supervisor(1000000, 1)
    register('pipeline', pl)
    sup_start_child(pl, {'sink', fun() { sink(0) }, 'permanent'})
    sup_start_child(pl, {'stage2_slow', fun() { stage2_slow() }, 'permanent'})
    sup_start_child(pl, {'stage1', fun() { stage1() }, 'permanent'})
    sup_start_child(pl, {'producer', fun() { producer(0) }, 'permanent'})

    cr = dyn_supervisor(1000000, 1)
    register('crashy', cr)
    start_n(cr, 24, fun(i) { fun() { crashy(i) } })

    tab = ets_new()
    gs = dyn_supervisor(1000000, 1)
    register('gossip', gs)
    start_gossip(gs, tab, 0)
    spawn(gossip_driver(tab))

    sl = dyn_supervisor(1000000, 1)
    register('sleepers', sl)
    start_n(sl, 120, fun(i) { fun() { sleeper() } })

    fat = dyn_supervisor(1000000, 1)
    register('fat', fat)
    sup_start_child(fat, {'hog_a', fun() { hog(60000) }, 'permanent'})
    sup_start_child(fat, {'hog_b', fun() { hog(120000) }, 'permanent'})
    sup_start_child(fat, {'hog_c', fun() { hog(30000) }, 'permanent'})

    LiveView.start(4009, [{"/", Observer.view(%{kill: 'true'})}])
}

fun start_gossip(sup, tab, i) {
    if (i >= 150) { 'ok' }
    else {
        sup_start_child(sup, {nil, fun() { gossiper(i, tab) }, 'permanent'})
        start_gossip(sup, tab, i + 1)
    }
}
