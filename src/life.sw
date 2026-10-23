module Main

# swarm-live — Life at Scale
#
#   make bin/life && scripts/run.sh life        ->  http://localhost:4011
#
# Conway's Game of Life where EVERY CELL IS A REAL SWARMRT PROCESS, up to
# 160 x 160 = 25,600 of them, each under a supervisor. A generation is pure
# message passing:
#
#     coordinator --{step}--> cell                      (1 message in)
#     cell --{s, state}--> its 8 neighbours             (8 messages out)
#     cell <--{s, state}-- its 8 neighbours             (8 messages in)
#     cell --{done}--> coordinator                      (1 message out)
#
# i.e. ~10 messages per cell per generation. Kill cells (chaos) and their
# supervisors restart them: the healer re-wires the newborn into its
# neighbours, it comes back dead, and Life grows around the wound.
#
# dyn_supervisor holds at most 4096 children (swarmrt#154), so the cells are
# spread over a pool of supervisors: two banks of 8, used alternately, so a
# rebuild never competes with the previous board's still-exiting children.

import LiveView
import LifeJs
import Std

let max_side = 160
let sup_bank = 8
let sup_count = 16

# ETS key space (all ints, sharded over 16 tables by key % 16):
#   i            -> pid of cell i
#   100000 + i   -> state of cell i (0/1)
#   200000 + i   -> start counter (1 = first start, >1 = restarted)
#   1000000 + k  -> pid of supervisor k
# control keys live in table tab + 16.
let k_state = 100000
let k_gen = 200000
let k_sup = 1000000

fun num(x) { if (x == nil) { 0 } else { x } }

# push a one-off event frame to every viewer right now (not tied to a generation)
fun ev(name, data) {
    LiveView.broadcast("life", {'frame', json_encode(%{t: "ev", n: name, d: data})})
}
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

fun idx(x, y, w) { ((y + w) % w) * w + ((x + w) % w) }

# ------------------------------------------------------------
# A cell is a process
# ------------------------------------------------------------
fun cell(i, tab, healer) {
    tput(tab, i, self())
    g = ets_update_counter(tab + (k_gen + i) % 16, k_gen + i, 1, 0)
    if (g > 1) { send(healer, {'hello', i, self()}) } else { 'first' }
    cell_wait(i, tab)
}

fun cell_wait(i, tab) {
    receive {
        {'init', st, nbrs, coord} ->
            tput(tab, k_state + i, st)
            cell_loop(i, tab, st, nbrs, coord)
        {'stop'} -> 'ok'
    }
}

fun cell_loop(i, tab, st, nbrs, coord) {
    receive {
        {'step'} ->
            tell(nbrs, st)
            n = gather(8, 0)
            nw = if (n == 3) { 1 } else { if (st == 1 && n == 2) { 1 } else { 0 } }
            tput(tab, k_state + i, nw)
            send(coord, {'done'})
            cell_loop(i, tab, nw, nbrs, coord)
        {'set', v} ->
            tput(tab, k_state + i, v)
            cell_loop(i, tab, v, nbrs, coord)
        {'rebind', k, pid} ->
            cell_loop(i, tab, st, set_nth(nbrs, k, pid), coord)
        {'stop'} -> 'ok'
    }
}

fun tell(nbrs, st) {
    if (length(nbrs) == 0) { 'ok' } else { send(hd(nbrs), {'s', st})  tell(tl(nbrs), st) }
}

# wait for the 8 neighbour states; a dead neighbour must not wedge the cell
fun gather(k, acc) {
    if (k <= 0) { acc }
    else {
        receive {
            {'s', v} -> gather(k - 1, acc + v)
            after 500 { acc }
        }
    }
}

fun set_nth(lst, k, v) {
    if (length(lst) == 0) { [] }
    else { if (k <= 0) { [v | tl(lst)] } else { [hd(lst) | set_nth(tl(lst), k - 1, v)] } }
}

# neighbour order: (-1,-1) (0,-1) (1,-1) (-1,0) (1,0) (-1,1) (0,1) (1,1);
# the opposite of direction d is 7 - d
fun nbr_pids(tab, x, y, w) {
    [tget(tab, idx(x - 1, y - 1, w)), tget(tab, idx(x, y - 1, w)), tget(tab, idx(x + 1, y - 1, w)),
     tget(tab, idx(x - 1, y, w)), tget(tab, idx(x + 1, y, w)),
     tget(tab, idx(x - 1, y + 1, w)), tget(tab, idx(x, y + 1, w)), tget(tab, idx(x + 1, y + 1, w))]
}

# ------------------------------------------------------------
# Healer — wires a restarted cell back into the grid
# ------------------------------------------------------------
fun healer(tab, acc) {
    receive {
        {'hello', i, pid} ->
            w = num(cget(tab, 'w'))
            if (w > 0) {
                x = i % w
                y = i / w
                tput(tab, k_state + i, 0)
                send(pid, {'init', 0, nbr_pids(tab, x, y, w), whereis('life_gen')})
                rebind(tab, 0, [idx(x - 1, y - 1, w), idx(x, y - 1, w), idx(x + 1, y - 1, w),
                                idx(x - 1, y, w), idx(x + 1, y, w),
                                idx(x - 1, y + 1, w), idx(x, y + 1, w), idx(x + 1, y + 1, w)], pid)
                healer(tab, [i | acc])
            } else { healer(tab, acc) }
        _o -> healer(tab, acc)
        after 30 {
            # flush respawns to the viewers as one event when the burst settles
            if (length(acc) > 0) { ev("revived", %{r: take_list(acc, 800), n: length(acc)}) } else { 'idle' }
            healer(tab, [])
        }
    }
}

fun rebind(tab, d, idxs, pid) {
    if (length(idxs) == 0) { 'ok' }
    else {
        np = tget(tab, hd(idxs))
        if (np == nil) { 'skip' } else { send(np, {'rebind', 7 - d, pid}) }
        rebind(tab, d + 1, tl(idxs), pid)
    }
}

# ------------------------------------------------------------
# Building / tearing down the board
# ------------------------------------------------------------
fun stop_cells(tab, i, n) {
    if (i >= n) { 'ok' }
    else {
        p = tget(tab, i)
        if (p == nil) { 'skip' } else { send(p, {'stop'}) }
        stop_cells(tab, i + 1, n)
    }
}

fun clear_keys(tab, i, n) {
    if (i >= n) { 'ok' }
    else {
        ets_delete(tab + i % 16, i)
        ets_delete(tab + (k_gen + i) % 16, k_gen + i)
        clear_keys(tab, i + 1, n)
    }
}

fun spawn_cells(tab, healer_pid, i, n, bank, failed) {
    if (i >= n) { failed }
    else {
        sup = cget(tab, k_sup + bank * sup_bank + i % sup_bank)
        r = sup_start_child(sup, {nil, fun() { cell(i, tab, healer_pid) }, 'transient'})
        spawn_cells(tab, healer_pid, i + 1, n, bank, if (r == nil) { failed + 1 } else { failed })
    }
}

fun wait_pid(tab, i, deadline) {
    if (tget(tab, i) == nil && timestamp() < deadline) { sleep(1)  wait_pid(tab, i, deadline) } else { 'ok' }
}

fun wait_pids(tab, i, n, deadline) {
    if (i >= n) { 'ok' } else { wait_pid(tab, i, deadline)  wait_pids(tab, i + 1, n, deadline) }
}

fun init_cells(tab, i, n, w, coord) {
    if (i >= n) { 'ok' }
    else {
        p = tget(tab, i)
        if (p == nil) { 'missing' } else { send(p, {'init', 0, nbr_pids(tab, i % w, i / w, w), coord}) }
        init_cells(tab, i + 1, n, w, coord)
    }
}

fun rebuild(tab, healer_pid, old_w, w) {
    if (old_w > 0) { stop_cells(tab, 0, old_w * old_w) } else { 'fresh' }
    sleep(if (old_w > 0) { 150 } else { 0 })
    n = w * w
    clear_keys(tab, 0, if (old_w * old_w > n) { old_w * old_w } else { n })
    cput(tab, 'w', 0)
    epoch = num(cget(tab, 'epoch')) + 1
    cput(tab, 'epoch', epoch)
    t0 = timestamp()
    failed = spawn_cells(tab, healer_pid, 0, n, epoch % 2, 0)
    wait_pids(tab, 0, n, timestamp() + 4000)
    t1 = timestamp()
    cput(tab, 'spawn_failed', failed)
    init_cells(tab, 0, n, w, self())
    cput(tab, 'w', w)
    cput(tab, 'spawn_ms', t1 - t0)
    cput(tab, 'want_pat', 'soup')
}

# ------------------------------------------------------------
# Patterns
# ------------------------------------------------------------
# two LCG rounds so neighbouring cells are decorrelated (one round makes stripes)
fun soup_value(i, w) {
    h1 = (i * 1103515245 + 12345) % 2147483648
    h2 = (h1 * 1103515245 + 12345) % 2147483648
    if ((h2 / 65536) % 100 < 30) { 1 } else { 0 }
}

fun seed_all(tab, i, n, w, name) {
    if (i >= n) { 'ok' }
    else {
        v = if (name == 'soup') { soup_value(i, w) } else { 0 }
        p = tget(tab, i)
        if (p == nil) { 'skip' } else { send(p, {'set', v}) }
        seed_all(tab, i + 1, n, w, name)
    }
}

fun place(tab, w, ox, oy, pts) {
    if (length(pts) == 0) { 'ok' }
    else {
        p = tget(tab, idx(ox + hd(hd(pts)), oy + hd(tl(hd(pts))), w))
        if (p == nil) { 'skip' } else { send(p, {'set', 1}) }
        place(tab, w, ox, oy, tl(pts))
    }
}

fun gun() {
    [[0,4],[0,5],[1,4],[1,5],[10,4],[10,5],[10,6],[11,3],[11,7],[12,2],[12,8],[13,2],[13,8],[14,5],[15,3],[15,7],
     [16,4],[16,5],[16,6],[17,5],[20,2],[20,3],[20,4],[21,2],[21,3],[21,4],[22,1],[22,5],[24,0],[24,1],[24,5],[24,6],
     [34,2],[34,3],[35,2],[35,3]]
}

fun seed(tab, w, name) {
    n = w * w
    seed_all(tab, 0, n, w, name)
    if (name == 'rpent') { place(tab, w, w / 2 - 1, w / 2 - 1, [[1,0],[2,0],[0,1],[1,1],[1,2]]) } else { 'no' }
    if (name == 'gun') { place(tab, w, 4, 4, gun()) } else { 'no' }
}

# ------------------------------------------------------------
# Generation loop (owns the barrier)
# ------------------------------------------------------------
fun step_all(tab, i, n) {
    if (i >= n) { 'ok' }
    else {
        p = tget(tab, i)
        if (p == nil) { 'skip' } else { send(p, {'step'}) }
        step_all(tab, i + 1, n)
    }
}

fun collect(k) {
    if (k <= 0) { 'ok' }
    else {
        receive {
            {'done'} -> collect(k - 1)
            after 800 { 'timeout' }
        }
    }
}

# 30 cells per integer: JSON-safe and compact (90,000 cells = 3,000 ints)
fun pack(tab, g, n) {
    if (g < 0) { [] } else { pack_groups(tab, g, n, []) }
}
fun pack_groups(tab, g, n, acc) {
    if (g < 0) { acc } else { pack_groups(tab, g - 1, n, [pack_one(tab, g * 30, 0, 0, n) | acc]) }
}
fun pack_one(tab, base, k, v, n) {
    if (k >= 30) { v }
    else {
        i = base + k
        s = if (i >= n) { 0 } else { num(tget(tab, k_state + i)) }
        pack_one(tab, base, k + 1, v * 2 + s, n)
    }
}

# live cells = set bits across the packed ints (no extra ETS reads)
fun pop_bits(lst, acc) {
    if (length(lst) == 0) { acc } else { pop_bits(tl(lst), bit_count(hd(lst), acc)) }
}
fun bit_count(v, acc) {
    if (v <= 0) { acc } else { bit_count(v / 2, acc + v % 2) }
}

fun take_list(lst, k) { Std.take(lst, k) }

fun frame(tab, w, gen) {
    n = w * w
    now = timestamp()
    wt = num(cget(tab, 'win_t'))
    wn = num(cget(tab, 'win_n'))
    gps = if (wt > 0 && now > wt) { wn * 1000 / (now - wt) } else { 0 }
    if (now - wt > 1000) { cput(tab, 'win_t', now)  cput(tab, 'win_n', 0)  cput(tab, 'gps', gps) } else { 'win' }
    st = swarm_stats()
    shown = num(cget(tab, 'gps'))
    g2 = if (shown > 0) { shown } else { gps }
    bits = pack(tab, (n - 1) / 30, n)
    LiveView.broadcast("life", {'frame', json_encode(%{t: "ev", n: "frame", d: %{
        w: w,
        gen: gen,
        b: bits,
        pop: pop_bits(bits, 0),
        procs: num(map_get(st, 'processes')),
        gps: g2,
        mps: g2 * n * 10,
        spms: num(cget(tab, 'spawn_ms')),
        restarts: num(map_get(st, 'restarts')),
        crashes: num(map_get(st, 'crashes')),
        paused: num(cget(tab, 'paused')),
        delay: num(cget(tab, 'delay')),
        sl: num(cget(tab, 'sleepers')),
        slms: num(cget(tab, 'sleep_ms')),
        sll: num(cget(tab, 'sleep_last')),
        k: [],
        r: []
    }})})
}

fun gen_loop(tab, healer_pid, gen, last_frame) {
    w = num(cget(tab, 'w'))
    want = num(cget(tab, 'want_w'))
    if (want > 0 && want != w) {
        cput(tab, 'want_w', 0)
        rebuild(tab, healer_pid, w, want)
        cput(tab, 'win_t', timestamp())
        cput(tab, 'win_n', 0)
        gen_loop(tab, healer_pid, 0, 0)
    } else {
        pat = cget(tab, 'want_pat')
        if (pat != nil && w > 0) {
            cput(tab, 'want_pat', nil)
            seed(tab, w, pat)
            sleep(40)
            gen_loop(tab, healer_pid, 0, 0)
        } else {
            if (w == 0) { sleep(20)  gen_loop(tab, healer_pid, gen, last_frame) }
            else {
                t0 = timestamp()
                paused = num(cget(tab, 'paused'))
                if (paused == 1) {
                    if (t0 - last_frame > 400) { frame(tab, w, gen) } else { 'idle' }
                    sleep(30)
                    gen_loop(tab, healer_pid, gen, if (t0 - last_frame > 400) { t0 } else { last_frame })
                } else {
                    step_all(tab, 0, w * w)
                    collect(w * w)
                    cput(tab, 'win_n', num(cget(tab, 'win_n')) + 1)
                    now = timestamp()
                    due = now - last_frame >= 33
                    if (due) { frame(tab, w, gen + 1) } else { 'skip' }
                    delay = num(cget(tab, 'delay'))
                    spent = timestamp() - t0
                    if (delay > spent) { sleep(delay - spent) } else { 'full' }
                    gen_loop(tab, healer_pid, gen + 1, if (due) { now } else { last_frame })
                }
            }
        }
    }
}

# ------------------------------------------------------------
# Command inbox (events from viewers)
# ------------------------------------------------------------
fun inbox(tab) {
    receive {
        {'size', w} ->
            cput(tab, 'want_w', if (w > max_side) { max_side } else { w })
            inbox(tab)
        {'pattern', name} ->
            cput(tab, 'want_pat', name)
            inbox(tab)
        {'pause'} ->
            cput(tab, 'paused', 1 - num(cget(tab, 'paused')))
            inbox(tab)
        {'speed', ms} ->
            cput(tab, 'delay', ms)
            inbox(tab)
        {'paint', csv, v} ->
            paint(tab, string_split(csv, ","), v)
            inbox(tab)
        {'chaos', pct} ->
            w = num(cget(tab, 'w'))
            killed = kill_random(tab, w * w * pct / 100, w * w, [])
            ev("kills", %{k: take_list(killed, 800), n: length(killed)})
            inbox(tab)
        {'sleepers', n} ->
            spawn_sleepers(tab, n)
            inbox(tab)
        {'release'} ->
            release_sleepers(tab)
            inbox(tab)
        _o -> inbox(tab)
    }
}

fun sleeper() {
    receive {
        {'stop'} -> 'ok'
        _o -> sleeper()
    }
}

# plain idle processes: ~10-20 KB each, so tens of thousands are cheap
fun spawn_sleepers(tab, n) {
    st = swarm_stats()
    room = 99000 - num(map_get(st, 'processes'))
    k = if (n > room) { room } else { n }
    have = num(cget(tab, 'sleepers'))
    t0 = timestamp()
    sl_spawn(tab, have, have + k)
    cput(tab, 'sleepers', have + k)
    cput(tab, 'sleep_ms', timestamp() - t0)
    cput(tab, 'sleep_last', k)
}

fun sl_spawn(tab, i, stop) {
    if (i >= stop) { 'ok' } else { ets_put(tab + 16, 2000000 + i, spawn(sleeper()))  sl_spawn(tab, i + 1, stop) }
}

fun release_sleepers(tab) {
    n = num(cget(tab, 'sleepers'))
    sl_stop(tab, 0, n)
    cput(tab, 'sleepers', 0)
}

fun sl_stop(tab, i, n) {
    if (i >= n) { 'ok' }
    else {
        p = ets_get(tab + 16, 2000000 + i)
        if (p == nil) { 'skip' } else { send(p, {'stop'}) }
        ets_delete(tab + 16, 2000000 + i)
        sl_stop(tab, i + 1, n)
    }
}

fun paint(tab, items, v) {
    if (length(items) == 0) { 'ok' }
    else {
        i = to_int(hd(items))
        w = num(cget(tab, 'w'))
        if (i != nil && i >= 0 && i < w * w) {
            p = tget(tab, i)
            if (p == nil) { 'skip' } else { send(p, {'set', v}) }
        } else { 'bad' }
        paint(tab, tl(items), v)
    }
}

# a real random index: 6 hex digits (24 bits) of a v4 UUID. An LCG over a
# 64-wide board draws visible diagonal stripes, so don't.
fun hexv(u, k) {
    v = ord(string_sub(u, k, 1))
    if (v < 58) { v - 48 } else { v - 87 }
}

fun rand_idx(n) {
    u = uuid()
    x = ((((hexv(u, 0) * 16 + hexv(u, 1)) * 16 + hexv(u, 2)) * 16 + hexv(u, 3)) * 16 + hexv(u, 4)) * 16 + hexv(u, 5)
    x % n
}

fun kill_random(tab, k, n, acc) {
    if (k <= 0 || n <= 0) { acc }
    else {
        i = rand_idx(n)
        p = tget(tab, i)
        if (p == nil) { kill_random(tab, k - 1, n, acc) }
        else {
            exit_proc(p, 'killed')
            kill_random(tab, k - 1, n, [i | acc])
        }
    }
}

fun inbox_send(msg) {
    a = whereis('life_in')
    if (a == nil) { 'noop' } else { send(a, msg) }
}

# ------------------------------------------------------------
# View — static shell; motion is in life.js
# ------------------------------------------------------------
fun mount(params) {
    if (LiveView.connected(params) == 'true') { LiveView.subscribe("life") } else { 'noop' }
    %{}
}

fun stat(id, label) {
    "<div class=\"card stat\"><div class=\"lbl\">" ++ label ++ "</div><div class=\"val\" id=\"v-" ++ id ++ "\">&ndash;</div>" ++
    "<div class=\"chip\" id=\"d-" ++ id ++ "\"></div></div>"
}

fun seg(attr, items) {
    "<div class=\"seg\">" ++ items ++ "</div>"
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
    ".body{flex:1;min-height:0;display:grid;grid-template-columns:1fr 340px;gap:14px}" ++
    ".board{position:relative;overflow:hidden;display:flex;align-items:center;justify-content:center;background:#050507}" ++
    "#life-cv{display:block;image-rendering:pixelated;cursor:crosshair}" ++
    ".bh{position:absolute;top:14px;left:16px;font-size:12px;color:var(--mu);pointer-events:none}.bh b{color:var(--tx)}" ++
    ".col{display:flex;flex-direction:column;gap:14px;min-height:0;overflow:auto}" ++
    ".col .card{padding:14px 16px;flex:none}.col h3{font-size:12px;font-weight:600;margin:0 0 10px}" ++
    ".seg{display:flex;gap:2px;background:#111;border:1px solid var(--line);border-radius:8px;padding:2px;margin-bottom:10px}" ++
    ".seg button{flex:1;font:inherit;font-size:11px;color:var(--mu);background:transparent;border:0;border-radius:6px;padding:6px 4px;cursor:pointer;transition:all .15s}" ++
    ".seg button:hover{color:var(--tx)}.seg button.on{background:#232323;color:var(--tx)}" ++
    ".row2{display:flex;gap:8px}.btn{flex:1;font:inherit;font-size:12px;font-weight:500;color:var(--tx);background:#111;border:1px solid var(--line2);border-radius:8px;padding:8px 10px;cursor:pointer;transition:all .15s}" ++
    ".btn:hover{background:#1a1a1a;border-color:#444}.btn.danger{color:#ff9a9a;border-color:#5b2020;background:#1a0b0b}.btn.danger:hover{background:#2a1010;border-color:var(--red)}" ++
    ".how{font-size:12px;color:var(--mu);line-height:1.6}.how b{color:var(--tx);font-weight:600}.how code{font:11px ui-monospace,Menlo,monospace;color:#cfcfcf;background:#141414;padding:1px 5px;border-radius:4px}" ++
    ".msg{display:grid;grid-template-columns:auto 1fr;gap:4px 10px;font:11px ui-monospace,Menlo,monospace;color:#9a9a9a;margin-top:8px}.msg i{font-style:normal;color:#ededed}" ++
    "@media(max-width:1080px){.cards{grid-template-columns:repeat(2,1fr)}.body{grid-template-columns:1fr}body{overflow:auto}#live-root{height:auto}.board{height:520px}}" ++
    "</style>"
}

fun render(assigns) {
    LiveView.h(
        css() ++
        "<header class=\"nav\"><div class=\"logo\">" ++
        "<svg width=\"22\" height=\"22\" viewBox=\"0 0 22 22\"><rect x=\"3\" y=\"3\" width=\"6\" height=\"6\" fill=\"#ededed\"/><rect x=\"13\" y=\"3\" width=\"6\" height=\"6\" fill=\"#555\"/><rect x=\"3\" y=\"13\" width=\"6\" height=\"6\" fill=\"#555\"/><rect x=\"13\" y=\"13\" width=\"6\" height=\"6\" fill=\"#ededed\"/></svg>" ++
        "Life at Scale</div><span class=\"crumb\">every cell is a process</span>" ++
        "<div class=\"live\"><span class=\"dot\"></span>live &middot; <span id=\"o-fps\">0</span> fps</div></header>" ++
        "<div class=\"main\"><div class=\"cards\">" ++
        stat("procs", "Processes alive") ++ stat("gps", "Generations / s") ++ stat("mps", "Messages / s") ++
        stat("pop", "Live cells") ++ stat("heal", "Self-healed") ++
        "</div><div class=\"body\">" ++
        "<div class=\"card board\" id=\"board\"><canvas id=\"life-cv\" sw-keep></canvas>" ++
        "<div class=\"bh\" id=\"bh\" sw-keep>draw with your mouse</div></div>" ++
        "<div class=\"col\">" ++
        "<div class=\"card\"><h3>Board &mdash; one process per square</h3><div class=\"seg\" id=\"seg-size\">" ++
        "<button data-size=\"32\">1k</button><button data-size=\"64\">4.1k</button><button data-size=\"100\">10k</button><button data-size=\"130\">16.9k</button><button data-size=\"160\">25.6k</button></div>" ++
        "<h3>Pattern</h3><div class=\"seg\"><button data-pat=\"soup\">Soup</button><button data-pat=\"rpent\">R-pentomino</button><button data-pat=\"gun\">Glider gun</button><button data-pat=\"clear\">Clear</button></div>" ++
        "<h3>Speed</h3><div class=\"seg\" id=\"seg-speed\"><button data-speed=\"200\">5/s</button><button data-speed=\"100\">10/s</button><button data-speed=\"33\">30/s</button><button data-speed=\"0\">max</button></div>" ++
        "<div class=\"row2\"><button class=\"btn\" id=\"b-pause\">Pause</button></div></div>" ++
        "<div class=\"card\"><h3>Chaos &mdash; kill live processes</h3><div class=\"row2\">" ++
        "<button class=\"btn danger\" data-chaos=\"5\">Kill 5%</button><button class=\"btn danger\" data-chaos=\"25\">Kill 25%</button></div>" ++
        "<p class=\"how\" style=\"margin-top:10px\">Each kill is <code>exit_proc(pid, 'killed')</code>. The supervisor restarts the cell, the healer re-wires it into its neighbours, and it comes back dead. Watch Life grow around the wound.</p></div>" ++
        "<div class=\"card\"><h3>Raw scale &mdash; idle processes</h3>" ++
        "<div class=\"row2\"><button class=\"btn\" data-sleepers=\"10000\">+10,000 idle</button><button class=\"btn\" id=\"b-release\">Release</button></div>" ++
        "<p class=\"how\" style=\"margin-top:10px\" id=\"h-sleep\">Parked processes cost ~10-20 KB each. The board keeps running while you stack tens of thousands of them next to it. The runtime's ceiling is 100,000.</p></div>" ++
        "<div class=\"card\"><h3>How a generation works</h3><div class=\"how\">No shared board. Each cell is a <b>process</b> that only talks by message.</div>" ++
        "<div class=\"msg\"><i>1</i><span>step in from the coordinator</span><i>8</i><span>state sent to its neighbours</span><i>8</i><span>states received back</span><i>1</i><span>done sent to the coordinator</span></div>" ++
        "<p class=\"how\" style=\"margin-top:10px\"><b id=\"h-per\">10</b> messages per cell per generation, all of them real.</p></div>" ++
        "</div></div></div>",
        [])
}

fun handle_event(name, value, assigns) {
    if (name == "size") {
        inbox_send({'size', to_int(map_get(value, 'w'))})
    } else { if (name == "pattern") {
        inbox_send({'pattern', to_string(map_get(value, 'name'))})
    } else { if (name == "pause") {
        inbox_send({'pause'})
    } else { if (name == "speed") {
        inbox_send({'speed', to_int(map_get(value, 'ms'))})
    } else { if (name == "paint") {
        inbox_send({'paint', to_string(map_get(value, 'c')), to_int(map_get(value, 'v'))})
    } else { if (name == "chaos") {
        inbox_send({'chaos', to_int(map_get(value, 'p'))})
    } else { if (name == "sleepers") {
        inbox_send({'sleepers', to_int(map_get(value, 'n'))})
    } else { if (name == "release") {
        inbox_send({'release'})
    } else { 'noop' }}}}}}}}
    assigns
}

fun handle_info(msg, assigns) {
    conn = map_get(assigns, '_conn')
    if (conn != nil && elem(msg, 0) == 'frame') { ws_send(conn, elem(msg, 1)) } else { 'noop' }
    assigns
}

fun main() {
    tab = make_tables(ets_new(), 16)
    cput(tab, 'delay', 100)
    cput(tab, 'paused', 0)
    cput(tab, 'win_t', timestamp())
    cput(tab, 'win_n', 0)
    start_sups(tab, 0)
    hp = spawn(healer(tab, []))
    register('life_healer', hp)
    register('life_in', spawn(inbox(tab)))
    cput(tab, 'want_w', 64)
    register('life_gen', spawn(gen_loop(tab, hp, 0, 0)))
    LiveView.start(4011, [
        {"/", %{
            title: "Life at Scale",
            js: LifeJs.js(),
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
