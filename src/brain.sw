module Main

# swarm-live — Neuron Swarm
#
#   make bin/brain && scripts/run.sh brain         ->  http://localhost:4012
#
# A spiking neural network where EVERY NEURON IS A REAL SWARMRT PROCESS.
#
#   sensors (the world)  --spike-->  reservoir neurons  --spike-->  other reservoir neurons
#                                          |
#                                          +--{r, id}-->  4 motor neurons (up/down/left/right)
#
# Each reservoir neuron is a leaky integrate-and-fire cell: every 25 ms it leaks,
# and when its membrane potential crosses the threshold it SPIKES, i.e. sends a
# message to the 8 neurons it is wired to. Wiring is a deterministic hash of the
# neuron's id (so a restarted neuron is wired identically, with no rewiring step),
# and every spike resolves its targets' current pids through ETS, so killing a
# neuron never breaks the network.
#
# The creature chases food. Only the readout into the 4 motor neurons learns:
# online, with a normalised delta rule driven by a teacher signal (the direction
# of the food). The reservoir is a fixed random network, as in reservoir
# computing. "Lesion" permanently mutes neurons and the readout re-adapts.

import LiveView
import BrainJs
import Math
import Std

let max_n = 4800
let sup_bank = 2
let sup_count = 4
let tick_ms = 25
let fan = 8
let sensor_fan = 36

# ETS keys (ints, sharded over 16 tables by key % 16):
#   i                      -> pid of reservoir neuron i
#   900000 + m             -> pid of motor neuron m
#   800000 + i             -> 1 if neuron i is lesioned (stays mute even after a restart)
#   2000000 + m*100000 + i -> readout weight i -> motor m
#   1000000 + k            -> supervisor pids
# control keys live in table tab + 16.
let k_lesion = 800000
let k_motor = 900000
let k_sup = 1000000
let k_weight = 2000000

fun num(x) { if (x == nil) { 0 } else { x } }
fun numf(x) { if (x == nil) { 0.0 } else { x } }
fun list_or_empty(x) { if (x == nil) { [] } else { x } }
fun tget(tab, k) { ets_get(tab + k % 16, k) }
fun tput(tab, k, v) { ets_put(tab + k % 16, k, v) }
fun cget(tab, k) { ets_get(tab + 16, k) }
fun cput(tab, k, v) { ets_put(tab + 16, k, v) }

fun make_tables(base, more) {
    if (more <= 0) { base }
    else {
        id = ets_new()
        if (id == base + (17 - more)) { make_tables(base, more - 1) } else { panic("ets ids not contiguous") }
    }
}

# deterministic hash for wiring (two LCG rounds so neighbours are decorrelated)
fun hsh(a, b) {
    x = (a * 7919 + b * 104729 + 13) % 2147483648
    h1 = (x * 1103515245 + 12345) % 2147483648
    h2 = (h1 * 1103515245 + 12345) % 2147483648
    h2 / 65536
}

fun hexv(u, k) {
    v = ord(string_sub(u, k, 1))
    if (v < 58) { v - 48 } else { v - 87 }
}

# a real random float in [0, 1) from a v4 UUID
fun rndf() {
    u = uuid()
    x = (((hexv(u, 0) * 16 + hexv(u, 1)) * 16 + hexv(u, 2)) * 16 + hexv(u, 3)) * 16 + hexv(u, 4)
    to_float(x % 100000) / 100000.0
}

# ------------------------------------------------------------
# A reservoir neuron is a process (leaky integrate-and-fire)
# ------------------------------------------------------------
fun neuron(i, tab, n, world) {
    tput(tab, i, self())
    neuron_loop(i, tab, n, world, 0.0, 0, num(tget(tab, k_lesion + i)))
}

fun neuron_loop(i, tab, n, world, v, refr, dead) {
    receive {
        {'s', w} ->
            if (dead == 1) { neuron_loop(i, tab, n, world, 0.0, 0, dead) }
            else { neuron_loop(i, tab, n, world, v + w, refr, dead) }
        {'tick'} ->
            v2 = v * 0.86
            if (dead == 0 && v2 >= 1.0 && refr <= 0) {
                fire(i, tab, n, 0)
                send(world, {'f', i})
                neuron_loop(i, tab, n, world, 0.0, 2, dead)
            } else {
                neuron_loop(i, tab, n, world, if (dead == 1) { 0.0 } else { v2 }, if (refr > 0) { refr - 1 } else { 0 }, dead)
            }
        {'stop'} -> 'ok'
    }
}

# a spike: 6 excitatory + 2 inhibitory synapses onto hashed targets, plus the
# readout synapses onto the 4 motor neurons
fun fire(i, tab, n, k) {
    if (k >= fan) { fire_motors(tab, i, 0) }
    else {
        p = tget(tab, hsh(i, k) % n)
        if (p == nil) { 'skip' } else { send(p, {'s', if (k < 6) { 0.5 } else { 0.0 - 0.9 }}) }
        fire(i, tab, n, k + 1)
    }
}

fun fire_motors(tab, i, m) {
    if (m >= 4) { 'ok' }
    else {
        p = tget(tab, k_motor + m)
        if (p == nil) { 'skip' } else { send(p, {'r', i}) }
        fire_motors(tab, i, m + 1)
    }
}

# ------------------------------------------------------------
# A motor neuron is a process too — and it is where learning happens
# ------------------------------------------------------------
fun wkey(m, i) { k_weight + m * 100000 + i }

fun motor(m, tab, world) {
    tput(tab, k_motor + m, self())
    motor_loop(m, tab, world, 0.0, 0, [])
}

fun motor_loop(m, tab, world, y, cnt, recs) {
    receive {
        {'r', i} ->
            w = numf(tget(tab, wkey(m, i)))
            motor_loop(m, tab, world, y + w, cnt + 1, [{i, w} | recs])
        {'tick', t} ->
            target = if (t == 1) { 1.4 } else { 0.0 }
            if (num(cget(tab, 'learn')) == 1 && cnt > 0) {
                # normalised delta rule: spread the error over the synapses that just spiked
                adjust(tab, m, recs, 0.09 * (target - y) / to_float(cnt))
            } else { 'frozen' }
            if (y >= 0.7) { send(world, {'m', m}) } else { 'quiet' }
            motor_loop(m, tab, world, 0.0, 0, [])
        {'stop'} -> 'ok'
    }
}

fun adjust(tab, m, recs, step) {
    if (length(recs) == 0) { 'ok' }
    else {
        r = hd(recs)
        w = elem(r, 1) + step
        tput(tab, wkey(m, elem(r, 0)), if (w > 2.0) { 2.0 } else { if (w < 0.0 - 2.0) { 0.0 - 2.0 } else { w } })
        adjust(tab, m, tl(recs), step)
    }
}

# ------------------------------------------------------------
# Building the brain
# ------------------------------------------------------------
fun stop_all(tab, i, n) {
    if (i >= n) { 'ok' }
    else {
        p = tget(tab, i)
        if (p == nil) { 'skip' } else { send(p, {'stop'}) }
        stop_all(tab, i + 1, n)
    }
}

fun clear_keys(tab, i, n) {
    if (i >= n) { 'ok' }
    else {
        ets_delete(tab + i % 16, i)
        ets_delete(tab + (k_lesion + i) % 16, k_lesion + i)
        clear_weights(tab, 0, i)
        clear_keys(tab, i + 1, n)
    }
}

fun clear_weights(tab, m, i) {
    if (m >= 4) { 'ok' } else { ets_delete(tab + (wkey(m, i)) % 16, wkey(m, i))  clear_weights(tab, m + 1, i) }
}

fun spawn_neurons(tab, world, i, n, bank, failed) {
    if (i >= n) { failed }
    else {
        sup = cget(tab, k_sup + bank * sup_bank + i % sup_bank)
        r = sup_start_child(sup, {nil, fun() { neuron(i, tab, n, world) }, 'transient'})
        spawn_neurons(tab, world, i + 1, n, bank, if (r == nil) { failed + 1 } else { failed })
    }
}

fun wait_pids(tab, i, n, deadline) {
    if (i >= n) { 'ok' }
    else {
        if (tget(tab, i) == nil && timestamp() < deadline) { sleep(1)  wait_pids(tab, i, n, deadline) }
        else { wait_pids(tab, i + 1, n, deadline) }
    }
}

fun rebuild(tab, world, old_n, n) {
    if (old_n > 0) { stop_all(tab, 0, old_n) } else { 'fresh' }
    sleep(if (old_n > 0) { 120 } else { 0 })
    clear_keys(tab, 0, if (old_n > n) { old_n } else { n })
    cput(tab, 'n', 0)
    epoch = num(cget(tab, 'epoch')) + 1
    cput(tab, 'epoch', epoch)
    t0 = timestamp()
    spawn_neurons(tab, world, 0, n, epoch % 2, 0)
    wait_pids(tab, 0, n, timestamp() + 5000)
    cput(tab, 'spawn_ms', timestamp() - t0)
    cput(tab, 'n', n)
    cput(tab, 'lesioned', 0)
    reset_world(tab)
}

fun reset_world(tab) {
    cput(tab, 'cx', 0.5)
    cput(tab, 'cy', 0.5)
    cput(tab, 'fx', 0.8)
    cput(tab, 'fy', 0.3)
    cput(tab, 'eaten', 0)
    cput(tab, 'acc', 0.5)
    cput(tab, 'food_age', 0)
}

# ------------------------------------------------------------
# The world: sensors in, creature physics, teacher, frames out
# ------------------------------------------------------------
fun octant(dx, dy) {
    sx = if (dx > 0.0) { 1 } else { 0 }
    sy = if (dy > 0.0) { 1 } else { 0 }
    ax = if (dx < 0.0) { 0.0 - dx } else { dx }
    ay = if (dy < 0.0) { 0.0 - dy } else { dy }
    sx * 4 + sy * 2 + (if (ax > ay) { 0 } else { 1 })
}

fun dist_bin(d) { if (d < 0.18) { 0 } else { if (d < 0.42) { 1 } else { 2 } } }

# the sensor spikes into the reservoir: 36 hashed neurons get a nudge each tick
fun inject(tab, n, s, k) {
    if (k >= sensor_fan) { 'ok' }
    else {
        p = tget(tab, hsh(1000 + s, k) % n)
        if (p == nil) { 'skip' } else { send(p, {'s', 0.75}) }
        inject(tab, n, s, k + 1)
    }
}

fun tick_all(tab, i, n) {
    if (i >= n) { 'ok' }
    else {
        p = tget(tab, i)
        if (p == nil) { 'skip' } else { send(p, {'tick'}) }
        tick_all(tab, i + 1, n)
    }
}

fun tick_motors(tab, m, t0, t1, t2, t3) {
    if (m >= 4) { 'ok' }
    else {
        p = tget(tab, k_motor + m)
        t = if (m == 0) { t0 } else { if (m == 1) { t1 } else { if (m == 2) { t2 } else { t3 } } }
        if (p == nil) { 'skip' } else { send(p, {'tick', t}) }
        tick_motors(tab, m + 1, t0, t1, t2, t3)
    }
}

# drain what the neurons reported this tick: {fired ids, motor flags}
fun drain(fired, mf) {
    receive {
        {'f', i} -> drain([i | fired], mf)
        {'m', m} -> drain(fired, set_flag(mf, m))
        after 0 { {fired, mf} }
    }
}

fun set_flag(lst, k) {
    if (length(lst) == 0) { [] }
    else { if (k <= 0) { [1 | tl(lst)] } else { [hd(lst) | set_flag(tl(lst), k - 1)] } }
}

fun clamp01(x) { if (x < 0.02) { 0.02 } else { if (x > 0.98) { 0.98 } else { x } } }

fun flag(lst, k) { if (k <= 0) { hd(lst) } else { flag(tl(lst), k - 1) } }

fun world_loop(tab, tick) {
    n = num(cget(tab, 'n'))
    want = num(cget(tab, 'want_n'))
    if (want > 0 && want != n) {
        cput(tab, 'want_n', 0)
        rebuild(tab, self(), n, want)
        world_loop(tab, 0)
    } else {
        if (n == 0) { sleep(20)  world_loop(tab, tick) }
        else {
            t0 = timestamp()
            cx = numf(cget(tab, 'cx'))
            cy = numf(cget(tab, 'cy'))
            fx = numf(cget(tab, 'fx'))
            fy = numf(cget(tab, 'fy'))
            dx = fx - cx
            dy = fy - cy
            d = Math.sqrt(dx * dx + dy * dy)
            # teacher: which way the food is
            tr = if (dx > 0.02) { 1 } else { 0 }
            tl_ = if (dx < 0.0 - 0.02) { 1 } else { 0 }
            td = if (dy > 0.02) { 1 } else { 0 }
            tu = if (dy < 0.0 - 0.02) { 1 } else { 0 }
            sensor = octant(dx, dy) * 3 + dist_bin(d)
            inject(tab, n, sensor, 0)
            tick_all(tab, 0, n)
            tick_motors(tab, 0, tr, tl_, td, tu)
            sleep(11)
            got = drain([], [0, 0, 0, 0])
            fired = elem(got, 0)
            mf = elem(got, 1)
            # creature: motors steer, plus a little noise so it explores
            speed = 0.011
            vx = to_float(flag(mf, 0) - flag(mf, 1)) * speed + (rndf() - 0.5) * 0.004
            vy = to_float(flag(mf, 2) - flag(mf, 3)) * speed + (rndf() - 0.5) * 0.004
            nx = clamp01(cx + vx)
            ny = clamp01(cy + vy)
            ex = fx - nx
            ey = fy - ny
            ate = Math.sqrt(ex * ex + ey * ey) < 0.055
            age = num(cget(tab, 'food_age')) + 1
            if (ate || age > 90) {
                # a new food somewhere else (also every 2.2 s, so the teacher sees every direction)
                cput(tab, 'fx', 0.06 + rndf() * 0.88)
                cput(tab, 'fy', 0.06 + rndf() * 0.88)
                cput(tab, 'food_age', 0)
                if (ate) { cput(tab, 'eaten', num(cget(tab, 'eaten')) + 1) } else { 'missed' }
            } else { cput(tab, 'food_age', age) }
            cput(tab, 'cx', nx)
            cput(tab, 'cy', ny)
            # behaviour accuracy: do the 4 motors agree with the teacher?
            ok = (if (flag(mf, 0) == tr) { 1 } else { 0 }) + (if (flag(mf, 1) == tl_) { 1 } else { 0 }) +
                 (if (flag(mf, 2) == td) { 1 } else { 0 }) + (if (flag(mf, 3) == tu) { 1 } else { 0 })
            acc = numf(cget(tab, 'acc')) * 0.985 + (to_float(ok) / 4.0) * 0.015
            cput(tab, 'acc', acc)
            # rolling spike counters
            cput(tab, 'win_spikes', num(cget(tab, 'win_spikes')) + length(fired))
            cput(tab, 'win_ticks', num(cget(tab, 'win_ticks')) + 1)
            if (tick % 40 == 0) {
                cput(tab, 'sps', num(cget(tab, 'win_spikes')))
                cput(tab, 'win_spikes', 0)
                cput(tab, 'win_ticks', 0)
                cput(tab, 'topw', top_weights(tab, n))
            } else { 'x' }
            frame(tab, n, tick, fired, mf, sensor, nx, ny, acc, if (tick % 40 == 0) { 1 } else { 0 })
            spent = timestamp() - t0
            if (spent < tick_ms) { sleep(tick_ms - spent) } else { 'late' }
            world_loop(tab, tick + 1)
        }
    }
}

fun frame(tab, n, tick, fired, mf, sensor, cx, cy, acc, with_weights) {
    st = swarm_stats()
    sps = num(cget(tab, 'sps'))
    LiveView.broadcast("brain", {'frame', json_encode(%{t: "ev", n: "frame", d: %{
        n: n,
        tick: tick,
        s: fired,
        mo: mf,
        sn: sensor,
        c: [Math.round(cx * 1000), Math.round(cy * 1000)],
        f: [Math.round(numf(cget(tab, 'fx')) * 1000), Math.round(numf(cget(tab, 'fy')) * 1000)],
        eaten: num(cget(tab, 'eaten')),
        acc: Math.round(acc * 1000),
        procs: num(map_get(st, 'processes')),
        sps: sps,
        eps: sps * (fan + 4),
        learn: num(cget(tab, 'learn')),
        lz: num(cget(tab, 'lesioned')),
        spms: num(cget(tab, 'spawn_ms')),
        restarts: num(map_get(st, 'restarts')),
        tw: if (with_weights == 1) { list_or_empty(cget(tab, 'topw')) } else { [] }
    }})})
}

# the strongest learned synapses into each motor neuron: [[m, i, w*100], ...]
fun top_weights(tab, n) {
    list_append_all(top_for(tab, n, 0, 0, []), top_for(tab, n, 1, 0, []), top_for(tab, n, 2, 0, []), top_for(tab, n, 3, 0, []))
}

fun app(a, b) { if (length(a) == 0) { b } else { [hd(a) | app(tl(a), b)] } }
fun list_append_all(a, b, c, d) { app(a, app(b, app(c, d))) }

fun top_for(tab, n, m, i, acc) {
    if (i >= n) { acc }
    else {
        w = numf(tget(tab, wkey(m, i)))
        if (w > 0.12) { top_for(tab, n, m, i + 1, top_insert(acc, [m, i, Math.round(w * 100)], 18)) }
        else { top_for(tab, n, m, i + 1, acc) }
    }
}

# keep a list of the k largest items by weight (descending)
fun top_insert(lst, item, k) {
    merged = insert_sorted(lst, item)
    if (length(merged) > k) { Std.take(merged, k) } else { merged }
}

fun insert_sorted(lst, item) {
    if (length(lst) == 0) { [item] }
    else { if (hd(tl(tl(item))) >= hd(tl(tl(hd(lst))))) { [item | lst] } else { [hd(lst) | insert_sorted(tl(lst), item)] } }
}

# ------------------------------------------------------------
# Command inbox
# ------------------------------------------------------------
fun inbox(tab) {
    receive {
        {'size', n} ->
            cput(tab, 'want_n', if (n > max_n) { max_n } else { n })
            inbox(tab)
        {'learn'} ->
            cput(tab, 'learn', 1 - num(cget(tab, 'learn')))
            inbox(tab)
        {'forget'} ->
            n = num(cget(tab, 'n'))
            forget(tab, 0, n)
            cput(tab, 'acc', 0.5)
            inbox(tab)
        {'lesion', pct} ->
            n = num(cget(tab, 'n'))
            gone = lesion(tab, n * pct / 100, n, [])
            ev("lesions", %{l: Std.take(gone, 2500), n: length(gone)})
            inbox(tab)
        {'food', x, y} ->
            cput(tab, 'fx', x)
            cput(tab, 'fy', y)
            cput(tab, 'food_age', 0)
            inbox(tab)
        _o -> inbox(tab)
    }
}

fun forget(tab, i, n) {
    if (i >= n) { 'ok' } else { clear_weights(tab, 0, i)  forget(tab, i + 1, n) }
}

# lesion: mark neurons as dead tissue, then kill the processes. The supervisor
# restarts them, but they come back mute, so the damage is permanent.
fun lesion(tab, k, n, acc) {
    if (k <= 0 || n <= 0) { acc }
    else {
        i = rndi(n)
        if (num(cget(tab, 'lesioned')) >= n) { acc }
        else { if (num(tget(tab, k_lesion + i)) == 1) { lesion(tab, k, n, acc) }
        else {
            tput(tab, k_lesion + i, 1)
            p = tget(tab, i)
            if (p == nil) { 'skip' } else { exit_proc(p, 'killed') }
            cput(tab, 'lesioned', num(cget(tab, 'lesioned')) + 1)
            lesion(tab, k - 1, n, [i | acc])
        }}
    }
}

fun rndi(n) { Math.floor(rndf() * to_float(n)) }

fun ev(name, data) {
    LiveView.broadcast("brain", {'frame', json_encode(%{t: "ev", n: name, d: data})})
}

fun inbox_send(msg) {
    a = whereis('brain_in')
    if (a == nil) { 'noop' } else { send(a, msg) }
}

# ------------------------------------------------------------
# View — static shell; motion is in brain.js
# ------------------------------------------------------------
fun mount(params) {
    if (LiveView.connected(params) == 'true') { LiveView.subscribe("brain") } else { 'noop' }
    %{}
}

fun stat(id, label) {
    "<div class=\"card stat\"><div class=\"lbl\">" ++ label ++ "</div><div class=\"val\" id=\"v-" ++ id ++ "\">&ndash;</div>" ++
    "<div class=\"chip\" id=\"d-" ++ id ++ "\"></div></div>"
}

fun css() {
    "<style>" ++
    ":root{--bg:#000;--card:#0a0a0a;--line:#1f1f1f;--line2:#2e2e2e;--tx:#ededed;--mu:#8f8f8f;--blue:#3b9eff;--red:#ff4d4d;--green:#50e3c2}" ++
    "*{box-sizing:border-box}html,body{height:100%;background:var(--bg);color:var(--tx);margin:0}" ++
    "body{font-family:ui-sans-serif,-apple-system,'SF Pro Text',Inter,'Segoe UI',sans-serif;-webkit-font-smoothing:antialiased;overflow:hidden}" ++
    "#live-root{height:100%;display:flex;flex-direction:column}" ++
    ".nav{height:56px;flex:none;display:flex;align-items:center;gap:14px;padding:0 24px;border-bottom:1px solid var(--line)}" ++
    ".logo{display:flex;align-items:center;gap:10px;font-weight:600;font-size:14px}.crumb{color:var(--mu);font-size:14px}.crumb:before{content:'/';margin-right:14px;color:#3a3a3a}" ++
    ".live{margin-left:auto;display:flex;align-items:center;gap:8px;font-size:12px;color:var(--mu);padding:5px 11px;border:1px solid var(--line2);border-radius:99px}" ++
    ".dot{width:7px;height:7px;border-radius:50%;background:var(--green);animation:pulse 1.8s infinite}" ++
    "@keyframes pulse{70%{box-shadow:0 0 0 7px rgba(80,227,194,0)}100%{box-shadow:0 0 0 0 rgba(80,227,194,0)}}" ++
    ".main{flex:1;min-height:0;padding:20px 24px 24px;display:flex;flex-direction:column;gap:14px}" ++
    ".cards{display:grid;grid-template-columns:repeat(5,1fr);gap:14px;flex:none}" ++
    ".card{background:var(--card);border:1px solid var(--line);border-radius:12px}" ++
    ".stat{padding:14px 16px;height:98px}.lbl{font-size:12px;color:var(--mu)}" ++
    ".val{font-size:30px;font-weight:600;letter-spacing:-.03em;font-variant-numeric:tabular-nums;margin-top:3px}" ++
    ".chip{font-size:11px;color:var(--mu);margin-top:1px}.chip.up{color:var(--green)}.chip.bad{color:var(--red)}" ++
    ".body{flex:1;min-height:0;display:grid;grid-template-columns:1fr 360px;gap:14px}" ++
    ".brain{position:relative;overflow:hidden;background:#040406}#brain-cv{position:absolute;inset:0}" ++
    ".bh{position:absolute;top:14px;left:16px;font-size:12px;color:var(--mu);pointer-events:none}.bh b{color:var(--tx)}" ++
    ".legend{position:absolute;left:16px;bottom:14px;display:flex;gap:14px;font-size:11px;color:var(--mu);pointer-events:none}" ++
    ".legend i{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px}" ++
    ".col{display:flex;flex-direction:column;gap:14px;min-height:0;overflow:auto}" ++
    ".col .card{padding:14px 16px;flex:none}.col h3{font-size:12px;font-weight:600;margin:0 0 10px;display:flex;justify-content:space-between}" ++
    ".col h3 span{color:var(--mu);font-weight:400}" ++
    "#arena-cv{width:100%;aspect-ratio:1;display:block;border-radius:8px;background:#050507;cursor:crosshair}" ++
    "#chart-cv{width:100%;height:92px;display:block}" ++
    ".seg{display:flex;gap:2px;background:#111;border:1px solid var(--line);border-radius:8px;padding:2px;margin-bottom:10px}" ++
    ".seg button{flex:1;font:inherit;font-size:11px;color:var(--mu);background:transparent;border:0;border-radius:6px;padding:6px 4px;cursor:pointer;transition:all .15s}" ++
    ".seg button:hover{color:var(--tx)}.seg button.on{background:#232323;color:var(--tx)}" ++
    ".row2{display:flex;gap:8px}.btn{flex:1;font:inherit;font-size:12px;font-weight:500;color:var(--tx);background:#111;border:1px solid var(--line2);border-radius:8px;padding:8px 10px;cursor:pointer;transition:all .15s}" ++
    ".btn:hover{background:#1a1a1a;border-color:#444}.btn.on{background:#e6e6e6;color:#06070a;border-color:#e6e6e6}" ++
    ".btn.danger{color:#ff9a9a;border-color:#5b2020;background:#1a0b0b}.btn.danger:hover{background:#2a1010;border-color:var(--red)}" ++
    ".how{font-size:12px;color:var(--mu);line-height:1.6}.how b{color:var(--tx);font-weight:600}" ++
    "@media(max-width:1080px){.cards{grid-template-columns:repeat(2,1fr)}.body{grid-template-columns:1fr}body{overflow:auto}#live-root{height:auto}.brain{height:520px}}" ++
    "</style>"
}

fun render(assigns) {
    LiveView.h(
        css() ++
        "<header class=\"nav\"><div class=\"logo\">" ++
        "<svg width=\"22\" height=\"22\" viewBox=\"0 0 22 22\"><circle cx=\"5\" cy=\"11\" r=\"2.4\" fill=\"#ededed\"/><circle cx=\"11\" cy=\"5\" r=\"2.4\" fill=\"#555\"/><circle cx=\"11\" cy=\"17\" r=\"2.4\" fill=\"#555\"/><circle cx=\"17\" cy=\"11\" r=\"2.4\" fill=\"#ededed\"/><path d=\"M5 11L11 5L17 11L11 17Z\" fill=\"none\" stroke=\"#444\"/></svg>" ++
        "Neuron Swarm</div><span class=\"crumb\">every neuron is a process</span>" ++
        "<div class=\"live\"><span class=\"dot\"></span>live &middot; <span id=\"o-fps\">0</span> fps</div></header>" ++
        "<div class=\"main\"><div class=\"cards\">" ++
        stat("procs", "Neurons (processes)") ++ stat("sps", "Spikes / s") ++ stat("eps", "Synaptic events / s") ++
        stat("acc", "Behaviour accuracy") ++ stat("eat", "Food eaten") ++
        "</div><div class=\"body\">" ++
        "<div class=\"card brain\" id=\"brain\"><canvas id=\"brain-cv\" sw-keep></canvas>" ++
        "<div class=\"bh\" id=\"bh\" sw-keep>spikes are messages</div>" ++
        "<div class=\"legend\"><span><i style=\"background:#3b9eff\"></i>sensors</span><span><i style=\"background:#e6fbff\"></i>reservoir spike</span>" ++
        "<span><i style=\"background:#f5a623\"></i>motor neurons</span><span><i style=\"background:#50e3c2\"></i>learned synapses</span></div></div>" ++
        "<div class=\"col\">" ++
        "<div class=\"card\"><h3>The creature <span>click to place food</span></h3><canvas id=\"arena-cv\" sw-keep></canvas></div>" ++
        "<div class=\"card\"><h3>Learning curve <span id=\"h-acc\">accuracy over time</span></h3><canvas id=\"chart-cv\" sw-keep></canvas></div>" ++
        "<div class=\"card\"><h3>Brain size</h3><div class=\"seg\" id=\"seg-size\">" ++
        "<button data-size=\"600\">600</button><button data-size=\"1200\">1.2k</button><button data-size=\"2400\">2.4k</button><button data-size=\"4800\">4.8k</button></div>" ++
        "<h3>Experiments</h3><div class=\"row2\" style=\"margin-bottom:8px\"><button class=\"btn on\" id=\"b-learn\">Learning: on</button><button class=\"btn\" id=\"b-forget\">Forget</button></div>" ++
        "<div class=\"row2\"><button class=\"btn danger\" data-lesion=\"10\">Lesion 10%</button><button class=\"btn danger\" data-lesion=\"30\">Lesion 30%</button></div></div>" ++
        "<div class=\"card\"><h3>How it works</h3><p class=\"how\">Each neuron is a <b>process</b>. It leaks, and when its potential crosses 1.0 it <b>spikes</b>: a message to the 8 neurons it is wired to. Four motor neurons steer the creature. Only their input weights learn (a delta rule with a teacher signal), so you can watch it go from wandering to hunting. <b>Lesion</b> kills neurons for good; the readout re-adapts.</p></div>" ++
        "</div></div></div>",
        [])
}

fun handle_event(name, value, assigns) {
    if (name == "size") {
        inbox_send({'size', to_int(map_get(value, 'n'))})
    } else { if (name == "learn") {
        inbox_send({'learn'})
    } else { if (name == "forget") {
        inbox_send({'forget'})
    } else { if (name == "lesion") {
        inbox_send({'lesion', to_int(map_get(value, 'p'))})
    } else { if (name == "food") {
        inbox_send({'food', to_float(map_get(value, 'x')) / 1000.0, to_float(map_get(value, 'y')) / 1000.0})
    } else { 'noop' }}}}}
    assigns
}

fun handle_info(msg, assigns) {
    conn = map_get(assigns, '_conn')
    if (conn != nil && elem(msg, 0) == 'frame') { ws_send(conn, elem(msg, 1)) } else { 'noop' }
    assigns
}

fun main() {
    tab = make_tables(ets_new(), 16)
    cput(tab, 'learn', 1)
    start_sups(tab, 0)
    world = spawn(world_loop(tab, 0))
    register('brain_world', world)
    register('brain_in', spawn(inbox(tab)))
    start_motors(tab, world, 0)
    cput(tab, 'want_n', 2400)
    LiveView.start(4012, [
        {"/", %{
            title: "Neuron Swarm",
            js: BrainJs.js(),
            mount: mount,
            render: render,
            handle_event: handle_event,
            handle_info: handle_info
        }}
    ])
}

fun start_sups(tab, k) {
    if (k >= sup_count) { 'ok' }
    else {
        cput(tab, k_sup + k, dyn_supervisor(1000000, 1))
        start_sups(tab, k + 1)
    }
}

fun start_motors(tab, world, m) {
    if (m >= 4) { 'ok' }
    else { spawn(motor(m, tab, world))  start_motors(tab, world, m + 1) }
}
