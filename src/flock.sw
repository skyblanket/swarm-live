module Main

# swarm-live — Flock
#
#   make bin/flock && ./bin/flock      ->  http://localhost:4008
#
# 800 boids, each one a real swarmrt process. Every tick a coordinator
# bins the boids into a spatial grid (ETS) and pokes each boid; a boid reads
# its 3x3 neighbouring cells, steers (separation / alignment / cohesion plus
# predators), and writes its new state back. The coordinator then ws_sends
# one compact frame (positions + the flock's measured order) to every viewer
# and src/flock.js draws it.
#
# Every visitor is a predator the flock flees; hold the mouse button to
# become an attractor instead. The world wraps (torus).

import LiveView
import FlockJs
import Math
import Std

let n_boids = 800
let world_w = 1600.0
let world_h = 900.0
let cell = 80.0
let grid_x = 20
let grid_y = 12
let tick_ms = 33

# ETS keys: boid i's pid at i, its state {x, y, vx, vy} at 1000 + i,
# grid cell c's boid-index list at 100000 + c.
let k_state = 1000
let k_grid = 100000

fun num(x) { if (x == nil) { 0 } else { x } }
fun list_or_empty(x) { if (x == nil) { [] } else { x } }

# shortest signed distance on a wrapping axis
fun wd(d, size) {
    if (d > size / 2.0) { d - size } else { if (d < 0.0 - size / 2.0) { d + size } else { d } }
}

fun wrap(v, size) {
    if (v < 0.0) { v + size } else { if (v >= size) { v - size } else { v } }
}

# ------------------------------------------------------------
# Boids
# ------------------------------------------------------------
fun boid(i, tab) {
    ets_put(tab, i, self())
    boid_loop(i, tab, 0)
}

fun boid_loop(i, tab, tick) {
    receive {
        {'tick'} ->
            step(i, tab, tick)
            boid_loop(i, tab, tick + 1)
        _o ->
            boid_loop(i, tab, tick)
    }
}

fun cell_keys(cx, cy) {
    [k_grid + ((cy + 11) % grid_y) * grid_x + ((cx + 19) % grid_x),
     k_grid + ((cy + 11) % grid_y) * grid_x + (cx % grid_x),
     k_grid + ((cy + 11) % grid_y) * grid_x + ((cx + 1) % grid_x),
     k_grid + (cy % grid_y) * grid_x + ((cx + 19) % grid_x),
     k_grid + (cy % grid_y) * grid_x + (cx % grid_x),
     k_grid + (cy % grid_y) * grid_x + ((cx + 1) % grid_x),
     k_grid + ((cy + 1) % grid_y) * grid_x + ((cx + 19) % grid_x),
     k_grid + ((cy + 1) % grid_y) * grid_x + (cx % grid_x),
     k_grid + ((cy + 1) % grid_y) * grid_x + ((cx + 1) % grid_x)]
}

# acc = {count, sum vx, sum vy, sum dx, sum dy, sep x, sep y}
fun scan_idxs(tab, i, x, y, idxs, acc) {
    if (length(idxs) == 0) { acc }
    else {
        j = hd(idxs)
        if (j == i) { scan_idxs(tab, i, x, y, tl(idxs), acc) }
        else {
            s = ets_get(tab, k_state + j)
            if (s == nil) { scan_idxs(tab, i, x, y, tl(idxs), acc) }
            else {
                dx = wd(elem(s, 0) - x, world_w)
                dy = wd(elem(s, 1) - y, world_h)
                d2 = dx * dx + dy * dy
                if (d2 < 3600.0) {
                    sx = if (d2 < 700.0 && d2 > 0.01) { elem(acc, 5) - dx / d2 } else { elem(acc, 5) }
                    sy = if (d2 < 700.0 && d2 > 0.01) { elem(acc, 6) - dy / d2 } else { elem(acc, 6) }
                    scan_idxs(tab, i, x, y, tl(idxs),
                        {elem(acc, 0) + 1, elem(acc, 1) + elem(s, 2), elem(acc, 2) + elem(s, 3),
                         elem(acc, 3) + dx, elem(acc, 4) + dy, sx, sy})
                } else {
                    scan_idxs(tab, i, x, y, tl(idxs), acc)
                }
            }
        }
    }
}

fun scan_cells(tab, i, x, y, keys, acc) {
    if (length(keys) == 0) { acc }
    else {
        acc2 = scan_idxs(tab, i, x, y, list_or_empty(ets_get(tab, hd(keys))), acc)
        scan_cells(tab, i, x, y, tl(keys), acc2)
    }
}

# predators: {px, py, kind, hue}. kind 0 = repel, 1 = attract, 2 = blast.
# returns {fx, fy}
fun pred_force(preds, x, y, fx, fy) {
    if (length(preds) == 0) { {fx, fy} }
    else {
        p = hd(preds)
        dx = wd(elem(p, 0) - x, world_w)
        dy = wd(elem(p, 1) - y, world_h)
        d2 = dx * dx + dy * dy
        kind = elem(p, 2)
        if (kind == 1 && d2 < 160000.0 && d2 > 1.0) {
            d = Math.sqrt(d2)
            pull = 0.16 * (1.0 - d / 400.0)
            # pull in, plus a tangential push so the flock spirals round the cursor
            pred_force(tl(preds), x, y, fx + dx / d * pull - dy / d * pull * 0.9,
                                        fy + dy / d * pull + dx / d * pull * 0.9)
        } else { if (kind == 0 && d2 < 30000.0 && d2 > 1.0) {
            d = Math.sqrt(d2)
            push = 1.3 * (1.0 - d / 173.0)
            pred_force(tl(preds), x, y, fx - dx / d * push, fy - dy / d * push)
        } else { if (kind == 2 && d2 < 160000.0 && d2 > 1.0) {
            d = Math.sqrt(d2)
            push = 2.4 * (1.0 - d / 400.0)
            pred_force(tl(preds), x, y, fx - dx / d * push, fy - dy / d * push)
        } else {
            pred_force(tl(preds), x, y, fx, fy)
        }}}
    }
}

fun step(i, tab, tick) {
    s = ets_get(tab, k_state + i)
    x = elem(s, 0)
    y = elem(s, 1)
    vx = elem(s, 2)
    vy = elem(s, 3)
    cx = Math.floor(x / cell)
    cy = Math.floor(y / cell)
    acc = scan_cells(tab, i, x, y, cell_keys(cx, cy), {0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0})
    cnt = elem(acc, 0)
    mode = num(ets_get(tab, 'mode'))

    # the three flocking rules
    fc = if (cnt > 0) { to_float(cnt) } else { 1.0 }
    fx0 = if (cnt > 0) { (elem(acc, 1) / fc - vx) * 0.05 + elem(acc, 3) / fc * 0.006 + elem(acc, 5) * 3.4 } else { 0.0 }
    fy0 = if (cnt > 0) { (elem(acc, 2) / fc - vy) * 0.05 + elem(acc, 4) / fc * 0.006 + elem(acc, 6) * 3.4 } else { 0.0 }

    # mode 1 = swirl around the world centre, mode 2 = storm (jitter)
    rx = x - world_w / 2.0
    ry = y - world_h / 2.0
    fx1 = if (mode == 1) { fx0 - ry * 0.0011 - rx * 0.0003 } else { fx0 }
    fy1 = if (mode == 1) { fy0 + rx * 0.0011 - ry * 0.0003 } else { fy0 }
    jit = to_float((i * 7919 + tick * 104729) % 200 - 100) / 100.0
    jit2 = to_float((i * 104729 + tick * 7919) % 200 - 100) / 100.0
    fx2 = if (mode == 2) { fx1 + jit * 0.7 } else { fx1 }
    fy2 = if (mode == 2) { fy1 + jit2 * 0.7 } else { fy1 }

    pf = pred_force(list_or_empty(ets_get(tab, 'preds')), x, y, fx2, fy2)
    nvx0 = vx + elem(pf, 0)
    nvy0 = vy + elem(pf, 1)
    sp = Math.sqrt(nvx0 * nvx0 + nvy0 * nvy0)
    k = if (sp > 4.4) { 4.4 / sp } else { if (sp < 2.2 && sp > 0.01) { 2.2 / sp } else { 1.0 } }
    nvx = nvx0 * k
    nvy = nvy0 * k
    ets_put(tab, k_state + i, {wrap(x + nvx, world_w), wrap(y + nvy, world_h), nvx, nvy})
}

fun spawn_boids(sup, tab, i) {
    if (i >= n_boids) { 'ok' }
    else {
        ang = to_float((i * 7919) % 628) / 100.0
        ets_put(tab, k_state + i, {to_float((i * 104729) % 1600), to_float((i * 7907) % 900),
                                   Math.cos(ang) * 3.0, Math.sin(ang) * 3.0})
        sup_start_child(sup, {nil, fun() { boid(i, tab) }, 'permanent'})
        spawn_boids(sup, tab, i + 1)
    }
}

# ------------------------------------------------------------
# Coordinator — grid, tick, frame
# ------------------------------------------------------------
fun clear_grid(tab, c) {
    if (c >= grid_x * grid_y) { 'ok' }
    else { ets_put(tab, k_grid + c, [])  clear_grid(tab, c + 1) }
}

# bin every boid into its grid cell; accumulate order statistics.
# returns {sum vx, sum vy, sum speed}
fun bin(tab, j, svx, svy, ssp) {
    if (j >= n_boids) { {svx, svy, ssp} }
    else {
        s = ets_get(tab, k_state + j)
        c = (Math.floor(elem(s, 1) / cell) % grid_y) * grid_x + (Math.floor(elem(s, 0) / cell) % grid_x)
        ets_put(tab, k_grid + c, [j | list_or_empty(ets_get(tab, k_grid + c))])
        bin(tab, j + 1, svx + elem(s, 2), svy + elem(s, 3),
            ssp + Math.sqrt(elem(s, 2) * elem(s, 2) + elem(s, 3) * elem(s, 3)))
    }
}

fun poke(tab, j) {
    if (j >= n_boids) { 'ok' }
    else {
        pid = ets_get(tab, j)
        if (pid == nil) { 'skip' } else { send(pid, {'tick'}) }
        poke(tab, j + 1)
    }
}

# flat [x0, y0, x1, y1, ...] of rounded positions, ascending
fun positions(tab, j, acc) {
    if (j < 0) { acc }
    else {
        s = ets_get(tab, k_state + j)
        positions(tab, j - 1, [Math.round(elem(s, 0)), Math.round(elem(s, 1)) | acc])
    }
}

fun cons2(a, b, rest) { [a | [b | rest]] }

fun pred_json(preds, acc) {
    if (length(preds) == 0) { acc }
    else {
        p = hd(preds)
        pred_json(tl(preds), [[Math.round(elem(p, 0)), Math.round(elem(p, 1)), elem(p, 2), elem(p, 3)] | acc])
    }
}

fun coordinator(tab, tick) {
    clear_grid(tab, 0)
    st = bin(tab, 0, 0.0, 0.0, 0.0)
    poke(tab, 0)
    sp = elem(st, 2)
    pol = if (sp > 0.01) { Math.sqrt(elem(st, 0) * elem(st, 0) + elem(st, 1) * elem(st, 1)) / sp } else { 0.0 }
    preds = list_or_empty(ets_get(tab, 'preds'))
    LiveView.broadcast("flock", {'frame', json_encode(%{t: "ev", n: "frame", d: %{
        p: positions(tab, n_boids - 1, []),
        q: pred_json(preds, []),
        o: Math.round(pol * 1000),
        s: Math.round(sp / to_float(n_boids) * 100.0),
        n: n_boids,
        m: num(ets_get(tab, 'mode'))
    }})})
    sleep(tick_ms)
    coordinator(tab, tick + 1)
}

# ------------------------------------------------------------
# Pointer inbox — keeps the live predator list in ETS (separate process so
# a chatty cursor can never starve the coordinator's tick)
# ------------------------------------------------------------
fun inbox(tab, users) {
    receive {
        {'pointer', sid, x, y, kind, hue} ->
            u2 = map_put(users, sid, {x, y, kind, hue, timestamp()})
            publish(tab, u2)
            inbox(tab, u2)
        {'mode', m} ->
            ets_put(tab, 'mode', m)
            inbox(tab, users)
        {'blast', x, y} ->
            u2 = map_put(users, "blast-" ++ to_string(timestamp()), {x, y, 2, 20, timestamp() - 1000})
            publish(tab, u2)
            inbox(tab, u2)
        after 200 {
            u2 = prune(users)
            publish(tab, u2)
            inbox(tab, u2)
        }
    }
}

# drop anything quiet for 1.5s (blasts live ~500ms)
fun prune(users) { prune_keys(users, map_keys(users), timestamp()) }

fun prune_keys(users, keys, now) {
    if (length(keys) == 0) { users }
    else {
        u = map_get(users, hd(keys))
        if (now - elem(u, 4) > 1500) { prune_keys(map_remove(users, hd(keys)), tl(keys), now) }
        else { prune_keys(users, tl(keys), now) }
    }
}

fun publish(tab, users) {
    ets_put(tab, 'preds', pred_list(users, map_keys(users), []))
}

fun pred_list(users, keys, acc) {
    if (length(keys) == 0) { acc }
    else {
        u = map_get(users, hd(keys))
        pred_list(users, tl(keys), [{to_float(elem(u, 0)) * world_w, to_float(elem(u, 1)) * world_h, elem(u, 2), elem(u, 3)} | acc])
    }
}

fun inbox_send(msg) {
    a = whereis('flock_in')
    if (a == nil) { 'noop' } else { send(a, msg) }
}

# ------------------------------------------------------------
# View — static shell; all motion is in flock.js
# ------------------------------------------------------------
fun mount(params) {
    sid = uuid()
    if (LiveView.connected(params) == 'true') {
        LiveView.subscribe("flock")
        LiveView.presence_track("flock")
    } else {
        'noop'
    }
    %{sid: sid, hue: (ord(sid) * 37 + ord(string_sub(sid, 1, 1)) * 11) % 360}
}

fun render(assigns) {
    LiveView.h(
        "<style>" ++
        "html,body{height:100%;overflow:hidden;background:#06070a}" ++
        "#sky{position:fixed;inset:0;width:100vw;height:100vh;display:block;cursor:none}" ++
        ".hud{position:fixed;top:14px;left:20px;font-family:-apple-system,sans-serif;color:#e6e6e6;pointer-events:none}" ++
        ".hud h1{font-size:1.1rem;font-weight:600;letter-spacing:.02em}" ++
        ".hud p{font-size:.78rem;color:#7d8590;margin-top:2px}" ++
        ".panel{position:fixed;top:14px;right:16px;width:250px;font-family:-apple-system,sans-serif;color:#e6e6e6;" ++
        "background:rgba(14,16,20,.78);border:1px solid #23272e;border-radius:12px;padding:12px 14px;backdrop-filter:blur(6px)}" ++
        ".st{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:8px}" ++
        ".st span{font-size:.62rem;color:#7d8590;text-transform:uppercase;letter-spacing:.08em}" ++
        ".st b{font-size:1.15rem;font-variant-numeric:tabular-nums;font-weight:600}" ++
        ".meter{height:6px;border-radius:3px;background:#1a1d23;overflow:hidden;margin:2px 0 12px}" ++
        ".meter i{display:block;height:100%;width:0;background:linear-gradient(90deg,#1659a0,#4fd1e8,#e6fbff)}" ++
        ".bar{display:flex;gap:6px;flex-wrap:wrap}" ++
        ".btn{font:inherit;font-size:.8rem;font-weight:500;color:#e6e6e6;background:#14161a;" ++
        "border:1px solid #2a2f37;border-radius:8px;padding:.45rem .8rem;cursor:pointer;" ++
        "transition:background .08s,border-color .08s,transform .05s}" ++
        ".btn:hover{background:#1d2026;border-color:#3d434d}.btn:active{transform:scale(.95)}" ++
        ".btn.on{background:#e6e6e6;color:#06070a;border-color:#e6e6e6}" ++
        ".btn.hot{background:#2a0f0a;border-color:#7c2d12;color:#fdba74}" ++
        ".tip{font-size:.7rem;color:#7d8590;margin-top:10px;line-height:1.45}" ++
        "</style>" ++
        "<canvas id=\"sky\" sw-keep></canvas>" ++
        "<div class=\"hud\"><h1>Flock</h1>" ++
        "<p><span id=\"s-n\">800</span> boids &mdash; every one a real swarmrt process</p></div>" ++
        "<div class=\"panel\">" ++
        "<div class=\"st\"><span>order</span><b id=\"s-ord\">-</b></div>" ++
        "<div class=\"meter\"><i id=\"m-ord\"></i></div>" ++
        "<div class=\"st\"><span>avg speed</span><b id=\"s-spd\">-</b></div>" ++
        "<div class=\"st\"><span>viewers</span><b id=\"s-view\">1</b></div>" ++
        "<div class=\"st\"><span>frames / s</span><b id=\"s-fps\">-</b></div>" ++
        "<div class=\"bar\">" ++
        "<button class=\"btn\" data-mode=\"0\">flock</button>" ++
        "<button class=\"btn\" data-mode=\"1\">swirl</button>" ++
        "<button class=\"btn\" data-mode=\"2\">storm</button>" ++
        "<button class=\"btn hot\" data-blast=\"1\" style=\"margin-left:auto\">scatter</button></div>" ++
        "<p class=\"tip\">Move your mouse: you are a predator. Hold the button: you become an attractor.</p>" ++
        "</div>",
        [])
}

fun handle_event(name, value, assigns) {
    if (name == "ptr") {
        inbox_send({'pointer', map_get(assigns, 'sid'), map_get(value, 'x'), map_get(value, 'y'),
                    to_int(map_get(value, 'k')), map_get(assigns, 'hue')})
    } else { if (name == "mode") {
        inbox_send({'mode', to_int(map_get(value, 'm'))})
    } else { if (name == "blast") {
        inbox_send({'blast', map_get(value, 'x'), map_get(value, 'y')})
    } else {
        'noop'
    }}}
    assigns
}

# a frame is a finished JSON string; presence is forwarded as an ev frame
fun handle_info(msg, assigns) {
    conn = map_get(assigns, '_conn')
    tag = elem(msg, 0)
    if (tag == 'frame') {
        if (conn == nil) { 'noop' } else { ws_send(conn, elem(msg, 1)) }
    } else { if (tag == 'presence') {
        if (conn == nil) { 'noop' } else {
            ws_send(conn, json_encode(%{t: "ev", n: "presence", d: elem(msg, 2)}))
        }
    } else { 'noop' }}
    assigns
}

fun main() {
    tab = ets_new()
    ets_put(tab, 'mode', 0)
    ets_put(tab, 'preds', [])
    sup = dyn_supervisor(1000000, 1)
    spawn_boids(sup, tab, 0)
    register('flock_in', spawn(inbox(tab, map_new())))
    spawn(coordinator(tab, 0))
    LiveView.start(4008, %{
        title: "Flock",
        js: FlockJs.js(),
        mount: mount,
        render: render,
        handle_event: handle_event,
        handle_info: handle_info
    })
}
