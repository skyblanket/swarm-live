module Main

# swarm-live — Creature
#
#   make bin/creature && scripts/run.sh creature      ->  http://localhost:4013
#
# A creature with a body, senses and a brain made of thousands of swarmrt
# processes, living in a world with food, poison, obstacles and a predator.
#
#   BODY      energy (hunger) and health; every move costs energy; poison and bites hurt.
#   SENSES    7 vision rays (what is it, how far), 2 antennae smelling food and poison,
#             touch (bump) and pain, plus internal hunger and health — 106 sensors.
#   BRAIN     three regions of leaky integrate-and-fire neurons, each neuron a process:
#               visual (fed by vision), chemical (smell / touch / body), association
#               (fed by both). A spike is a message to the neurons it is wired to.
#   MOTORS    4 motor neurons: forward, turn +, turn -, boost.
#   LEARNING  only the readout into the motors learns, online, by a normalised delta
#             rule that copies a built-in expert (seek food, avoid poison, flee the
#             predator): behaviour cloning, not reinforcement learning. While the brain
#             is still bad, the expert "autopilot" drives the body; it hands over to
#             the brain as its accuracy improves.
#   LESION    permanently mutes neurons; the readout re-adapts.
#
# Every neuron's wiring is a hash of its id and targets are looked up by id at
# spike time, so a killed and restarted neuron is wired exactly as before.

import LiveView
import CreatureJs
import Math
import Std

let max_n = 4800
let sup_bank = 2
let sup_count = 4
let tick_ms = 25
let fan = 8
let sensor_fan = 22
let n_sensors = 106

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
fun fmin(a, b) { if (a < b) { a } else { b } }
fun fmax(a, b) { if (a > b) { a } else { b } }
fun fabs(a) { if (a < 0.0) { 0.0 - a } else { a } }
fun g(s, k) { map_get(s, k) }
fun p(s, k, v) { map_put(s, k, v) }

fun make_tables(base, more) {
    if (more <= 0) { base }
    else {
        id = ets_new()
        if (id == base + (17 - more)) { make_tables(base, more - 1) } else { panic("ets ids not contiguous") }
    }
}

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

fun rndf() {
    u = uuid()
    x = (((hexv(u, 0) * 16 + hexv(u, 1)) * 16 + hexv(u, 2)) * 16 + hexv(u, 3)) * 16 + hexv(u, 4)
    to_float(x % 100000) / 100000.0
}

# ------------------------------------------------------------
# Neurons are processes (leaky integrate-and-fire), in 3 regions
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

# region 0 = visual, 1 = chemical, 2 = association (n is a multiple of 3)
fun region_of(i, n) { i / (n / 3) }

# 4 synapses inside the region, 2 feed forward into the association region
# (association neurons stay in it), 2 inhibitory inside the region
fun fire(i, tab, n, k) {
    if (k >= fan) { fire_motors(tab, i, 0) }
    else {
        r = region_of(i, n)
        sz = n / 3
        tr = if (k < 4 || r == 2 || k >= 6) { r } else { 2 }
        t = tget(tab, tr * sz + hsh(i, k) % sz)
        if (t == nil) { 'skip' } else { send(t, {'s', if (k < 6) { 0.5 } else { 0.0 - 0.9 }}) }
        fire(i, tab, n, k + 1)
    }
}

fun fire_motors(tab, i, m) {
    if (m >= 4) { 'ok' }
    else {
        t = tget(tab, k_motor + m)
        if (t == nil) { 'skip' } else { send(t, {'r', i}) }
        fire_motors(tab, i, m + 1)
    }
}

# ------------------------------------------------------------
# Motor neurons: where the readout learns
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
        t = tget(tab, i)
        if (t == nil) { 'skip' } else { send(t, {'stop'}) }
        stop_all(tab, i + 1, n)
    }
}

fun clear_weights(tab, m, i) {
    if (m >= 4) { 'ok' } else { ets_delete(tab + (wkey(m, i)) % 16, wkey(m, i))  clear_weights(tab, m + 1, i) }
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
    wait_pids(tab, 0, n, timestamp() + 6000)
    cput(tab, 'spawn_ms', timestamp() - t0)
    cput(tab, 'n', n)
    cput(tab, 'lesioned', 0)
}

# ------------------------------------------------------------
# The world
# ------------------------------------------------------------
fun obstacles() { [[0.30, 0.35, 0.07], [0.70, 0.28, 0.06], [0.55, 0.72, 0.08], [0.18, 0.74, 0.06], [0.86, 0.80, 0.05]] }

fun in_obstacle(x, y, margin, obs) {
    if (length(obs) == 0) { 'false' }
    else {
        o = hd(obs)
        dx = x - hd(o)
        dy = y - hd(tl(o))
        r = hd(tl(tl(o))) + margin
        if (dx * dx + dy * dy < r * r) { 'true' } else { in_obstacle(x, y, margin, tl(obs)) }
    }
}

# a random free spot (a few tries, then give up and accept)
fun free_pos(tries) {
    x = 0.06 + rndf() * 0.88
    y = 0.06 + rndf() * 0.88
    if (tries <= 0 || in_obstacle(x, y, 0.04, obstacles()) == 'false') { [x, y] } else { free_pos(tries - 1) }
}

fun init_items(k, regrow) {
    if (k <= 0) { [] } else { [item_at(free_pos(30), regrow) | init_items(k - 1, regrow)] }
}
fun item_at(pos, regrow) { [hd(pos), hd(tl(pos)), regrow] }

fun new_world() {
    %{x: 0.5, y: 0.5, hx: 1.0, hy: 0.0, e: 80.0, h: 100.0, pain: 0, bump: 0, dead: 0, life: 0, best: 0,
      eaten: 0, poisoned: 0, bitten: 0, deaths: 0, cause: "",
      food: init_items(10, 0), poison: init_items(6, 0), pred: [0.88, 0.88, 0, 80, 0.0 - 1.0, 0.0],
      acc: 0.5, share: 0.85, ev: [], pred_on: 1}
}

# ---- vision: cast a ray, find the nearest thing ----
fun ray_circle(x, y, dx, dy, cx, cy, r) {
    ocx = cx - x
    ocy = cy - y
    tca = ocx * dx + ocy * dy
    if (tca < 0.0) { 99.0 }
    else {
        d2 = ocx * ocx + ocy * ocy - tca * tca
        r2 = r * r
        if (d2 > r2) { 99.0 } else { fmax(0.0, tca - Math.sqrt(r2 - d2)) }
    }
}

# best = {distance, type}; types: 0 food, 1 poison, 2 predator, 3 obstacle / wall
fun cast_items(lst, ty, rad, x, y, dx, dy, best, present_only) {
    if (length(lst) == 0) { best }
    else {
        it = hd(lst)
        gone = if (present_only == 1) { hd(tl(tl(it))) > 0 } else { false }
        t = if (gone) { 99.0 } else { ray_circle(x, y, dx, dy, hd(it), hd(tl(it)), rad) }
        cast_items(tl(lst), ty, rad, x, y, dx, dy, if (t < elem(best, 0)) { {t, ty} } else { best }, present_only)
    }
}

fun cast_obst(lst, x, y, dx, dy, best) {
    if (length(lst) == 0) { best }
    else {
        o = hd(lst)
        t = ray_circle(x, y, dx, dy, hd(o), hd(tl(o)), hd(tl(tl(o))))
        cast_obst(tl(lst), x, y, dx, dy, if (t < elem(best, 0)) { {t, 3} } else { best })
    }
}

fun wall_t(x, y, dx, dy) {
    tx = if (dx > 0.0) { (1.0 - x) / dx } else { if (dx < 0.0) { (0.0 - x) / dx } else { 99.0 } }
    ty = if (dy > 0.0) { (1.0 - y) / dy } else { if (dy < 0.0) { (0.0 - y) / dy } else { 99.0 } }
    fmin(tx, ty)
}

fun ray_cs(k) {
    if (k == 0) { {0.5, 0.0 - 0.866} } else { if (k == 1) { {0.766, 0.0 - 0.643} } else { if (k == 2) { {0.94, 0.0 - 0.342} } else {
    if (k == 3) { {1.0, 0.0} } else { if (k == 4) { {0.94, 0.342} } else { if (k == 5) { {0.766, 0.643} } else { {0.5, 0.866} } } } } } }
}

fun cast(s, k) {
    cs = ray_cs(k)
    hx = g(s, 'hx')
    hy = g(s, 'hy')
    dx = hx * elem(cs, 0) - hy * elem(cs, 1)
    dy = hx * elem(cs, 1) + hy * elem(cs, 0)
    x = g(s, 'x')
    y = g(s, 'y')
    pr = g(s, 'pred')
    b0 = {wall_t(x, y, dx, dy), 3}
    b1 = cast_obst(obstacles(), x, y, dx, dy, b0)
    b2 = cast_items(g(s, 'food'), 0, 0.025, x, y, dx, dy, b1, 1)
    b3 = cast_items(g(s, 'poison'), 1, 0.03, x, y, dx, dy, b2, 0)
    cast_items([[hd(pr), hd(tl(pr)), 0]], 2, 0.04, x, y, dx, dy, b3, 0)
}

# every ray: [[dist, type], ...]
fun all_rays(s, k) {
    if (k >= 7) { [] } else { [cast_pair(s, k) | all_rays(s, k + 1)] }
}
fun cast_pair(s, k) { r = cast(s, k)  [elem(r, 0), elem(r, 1)] }

fun ray_sensor(k, r) {
    t = hd(r)
    if (t > 0.45) { -1 } else { k * 12 + hd(tl(r)) * 3 + (if (t < 0.12) { 0 } else { if (t < 0.28) { 1 } else { 2 } }) }
}

fun vision_ids(rays, k) {
    if (length(rays) == 0) { [] }
    else {
        id = ray_sensor(k, hd(rays))
        if (id < 0) { vision_ids(tl(rays), k + 1) } else { [id | vision_ids(tl(rays), k + 1)] }
    }
}

# ---- smell: sum of Gaussians around items, by antenna ----
fun conc(lst, ax, ay, present_only, acc) {
    if (length(lst) == 0) { acc }
    else {
        it = hd(lst)
        gone = if (present_only == 1) { hd(tl(tl(it))) > 0 } else { false }
        dx = ax - hd(it)
        dy = ay - hd(tl(it))
        conc(tl(lst), ax, ay, present_only, if (gone) { acc } else { acc + Math.exp(0.0 - (dx * dx + dy * dy) / 0.04) })
    }
}

fun smell_level(c) { fmin(3.0, c * 2.0) }

fun smell_ids(s) {
    x = g(s, 'x')
    y = g(s, 'y')
    hx = g(s, 'hx')
    hy = g(s, 'hy')
    # antennae 0.03 ahead and 40 degrees to each side
    lx = x + 0.03 * (hx * 0.766 - hy * 0.643)
    ly = y + 0.03 * (hx * 0.643 + hy * 0.766)
    rx = x + 0.03 * (hx * 0.766 + hy * 0.643)
    ry = y + 0.03 * (0.0 - hx * 0.643 + hy * 0.766)
    ids0 = smell_one(84, conc(g(s, 'food'), lx, ly, 1, 0.0), [])
    ids1 = smell_one(87, conc(g(s, 'food'), rx, ry, 1, 0.0), ids0)
    ids2 = smell_one(90, conc(g(s, 'poison'), lx, ly, 0, 0.0), ids1)
    smell_one(93, conc(g(s, 'poison'), rx, ry, 0, 0.0), ids2)
}

fun smell_one(base, c, acc) {
    lv = Math.floor(smell_level(c))
    if (lv >= 1) { [base + lv - 1 | acc] } else { acc }
}

fun bin4(v) { if (v < 25.0) { 0 } else { if (v < 50.0) { 1 } else { if (v < 75.0) { 2 } else { 3 } } } }

fun body_ids(s) {
    a = if (g(s, 'pain') > 0) { [96] } else { [] }
    b = if (g(s, 'bump') > 0) { [97 | a] } else { a }
    [98 + bin4(g(s, 'e')), 102 + bin4(g(s, 'h')) | b]
}

fun app(a, b) { if (length(a) == 0) { b } else { [hd(a) | app(tl(a), b)] } }

fun sensor_ids(s, rays) {
    app(vision_ids(rays, 0), app(smell_ids(s), body_ids(s)))
}

# a sensor nudges neurons in its region: vision -> visual, everything else -> chemical
fun inject_all(tab, n, ids) {
    if (length(ids) == 0) { 'ok' }
    else { inject(tab, n, hd(ids), 0)  inject_all(tab, n, tl(ids)) }
}

fun inject(tab, n, sid, k) {
    if (k >= sensor_fan) { 'ok' }
    else {
        sz = n / 3
        region = if (sid < 84) { 0 } else { 1 }
        t = tget(tab, region * sz + hsh(1000 + sid, k) % sz)
        if (t == nil) { 'skip' } else { send(t, {'s', 0.75}) }
        inject(tab, n, sid, k + 1)
    }
}

# ---- the expert the brain learns from ----
fun nearest_food(lst, x, y, best) {
    if (length(lst) == 0) { best }
    else {
        it = hd(lst)
        present = hd(tl(tl(it))) <= 0
        dx = hd(it) - x
        dy = hd(tl(it)) - y
        d = Math.sqrt(dx * dx + dy * dy)
        nearer = present && (best == nil || d < hd(best))
        nearest_food(tl(lst), x, y, if (nearer) { [d, dx, dy] } else { best })
    }
}

# hazards close in front: nearest poison / obstacle with its direction
fun nearest_hazard(lst, rad, x, y, hx, hy, best) {
    if (length(lst) == 0) { best }
    else {
        it = hd(lst)
        dx = hd(it) - x
        dy = hd(tl(it)) - y
        d = Math.sqrt(dx * dx + dy * dy) - rad
        front = (hx * dx + hy * dy) > 0.0
        nearer = front && d < 0.13 && (best == nil || d < hd(best))
        nearest_hazard(tl(lst), rad, x, y, hx, hy, if (nearer) { [d, dx, dy] } else { best })
    }
}

fun obst_as_hazards(lst, x, y, hx, hy, best) {
    if (length(lst) == 0) { best }
    else {
        o = hd(lst)
        dx = hd(o) - x
        dy = hd(tl(o)) - y
        d = Math.sqrt(dx * dx + dy * dy) - hd(tl(tl(o)))
        front = (hx * dx + hy * dy) > 0.0
        nearer = front && d < 0.10 && (best == nil || d < hd(best))
        obst_as_hazards(tl(lst), x, y, hx, hy, if (nearer) { [d, dx, dy] } else { best })
    }
}

# steer toward a direction: {turn+, turn-, facing}
fun steer(hx, hy, dx, dy) {
    len = Math.sqrt(dx * dx + dy * dy) + 0.000001
    cross = (hx * dy - hy * dx) / len
    dot = (hx * dx + hy * dy) / len
    pos = if (cross > 0.12 || (dot < 0.0 && cross >= 0.0)) { 1 } else { 0 }
    neg = if (cross < 0.0 - 0.12 || (dot < 0.0 && cross < 0.0)) { 1 } else { 0 }
    # walk in arcs: keep moving unless the target is behind us
    {pos, neg, if (dot > 0.0 - 0.2) { 1 } else { 0 }}
}

# returns {fwd, turn+, turn-, boost}
fun expert(s) {
    x = g(s, 'x')
    y = g(s, 'y')
    hx = g(s, 'hx')
    hy = g(s, 'hy')
    pr = g(s, 'pred')
    pdx = x - hd(pr)
    pdy = y - hd(tl(pr))
    pd = Math.sqrt(pdx * pdx + pdy * pdy)
    mode = hd(tl(tl(pr)))
    poi = nearest_hazard(g(s, 'poison'), 0.03, x, y, hx, hy, nil)
    haz = obst_as_hazards(obstacles(), x, y, hx, hy, poi)
    wall = x < 0.07 || x > 0.93 || y < 0.07 || y > 0.93
    if (g(s, 'pred_on') == 1 && pd < 0.34 && mode != 2) {
        wd = fmin(fmin(x, 1.0 - x), fmin(y, 1.0 - y))
        wf = if (wd < 0.22) { 1.6 * (0.22 - wd) / 0.22 } else { 0.0 }
        cl = Math.sqrt((0.5 - x) * (0.5 - x) + (0.5 - y) * (0.5 - y)) + 0.000001
        fdx = pdx / (pd + 0.000001) + (0.5 - x) / cl * wf
        fdy = pdy / (pd + 0.000001) + (0.5 - y) / cl * wf
        st = steer(hx, hy, fdx, fdy)
        {elem(st, 2), elem(st, 0), elem(st, 1), if (pd < 0.24) { 1 } else { 0 }}
    } else { if (haz != nil) {
        # turn away from the hazard: steer toward the opposite direction
        st = steer(hx, hy, 0.0 - hd(tl(haz)), 0.0 - hd(tl(tl(haz))))
        {if (hd(haz) < 0.03) { 0 } else { elem(st, 2) }, elem(st, 0), elem(st, 1), 0}
    } else { if (wall) {
        st = steer(hx, hy, 0.5 - x, 0.5 - y)
        {elem(st, 2), elem(st, 0), elem(st, 1), 0}
    } else {
        food = nearest_food(g(s, 'food'), x, y, nil)
        if (food != nil && g(s, 'e') < 92.0) {
            st = steer(hx, hy, hd(tl(food)), hd(tl(tl(food))))
            {elem(st, 2), elem(st, 0), elem(st, 1), 0}
        } else {
            r = rndf()
            {1, if (r < 0.06) { 1 } else { 0 }, if (r > 0.94) { 1 } else { 0 }, 0}
        }
    }}}
}

# ---- physics ----
fun rotate_h(hx, hy, ang) {
    c = Math.cos(ang)
    sn = Math.sin(ang)
    nx = hx * c - hy * sn
    ny = hx * sn + hy * c
    len = Math.sqrt(nx * nx + ny * ny) + 0.000001
    {nx / len, ny / len}
}

fun push_out(x, y, obs) {
    if (length(obs) == 0) { {x, y, 0} }
    else {
        o = hd(obs)
        dx = x - hd(o)
        dy = y - hd(tl(o))
        r = hd(tl(tl(o))) + 0.02
        d2 = dx * dx + dy * dy
        if (d2 < r * r) {
            d = Math.sqrt(d2) + 0.000001
            {hd(o) + dx / d * r, hd(tl(o)) + dy / d * r, 1}
        } else { push_out(x, y, tl(obs)) }
    }
}

fun clampw(v) { if (v < 0.02) { 0.02 } else { if (v > 0.98) { 0.98 } else { v } } }

# cmd = {fwd, turn+, turn-, boost}
fun move(s, cmd) {
    ang = 0.11 * to_float(elem(cmd, 1) - elem(cmd, 2))
    hh = rotate_h(g(s, 'hx'), g(s, 'hy'), ang)
    speed = if (elem(cmd, 0) == 1) { if (elem(cmd, 3) == 1) { 0.0175 } else { 0.0100 } } else { 0.0 }
    nx = g(s, 'x') + elem(hh, 0) * speed
    ny = g(s, 'y') + elem(hh, 1) * speed
    po = push_out(nx, ny, obstacles())
    cx = clampw(elem(po, 0))
    cy = clampw(elem(po, 1))
    bumped = if (elem(po, 2) == 1 || cx != elem(po, 0) || cy != elem(po, 1)) { 1 } else { 0 }
    cost = 0.035 + speed * 1.5 + (if (elem(cmd, 3) == 1 && elem(cmd, 0) == 1) { 0.05 } else { 0.0 })
    p(p(p(p(p(s, 'x', cx), 'y', cy), 'hx', elem(hh, 0)), 'hy', elem(hh, 1)), 'bump', bumped)
        |> energy_cost(cost)
}

fun energy_cost(s, c) { p(s, 'e', g(s, 'e') - c) }

fun add_ev(s, code) { p(s, 'ev', [code | g(s, 'ev')]) }

# ---- eating, poison, regrowth ----
fun food_step(lst, x, y, acc, ate) {
    if (length(lst) == 0) { {acc, ate} }
    else {
        it = hd(lst)
        t = hd(tl(tl(it)))
        if (t > 0) {
            # regrowing: when the timer hits 0 it reappears somewhere new
            if (t == 1) { food_step(tl(lst), x, y, [item_at(free_pos(30), 0) | acc], ate) }
            else { food_step(tl(lst), x, y, [[hd(it), hd(tl(it)), t - 1] | acc], ate) }
        } else {
            dx = hd(it) - x
            dy = hd(tl(it)) - y
            if (dx * dx + dy * dy < 0.0016) { food_step(tl(lst), x, y, [[hd(it), hd(tl(it)), 90] | acc], ate + 1) }
            else { food_step(tl(lst), x, y, [it | acc], ate) }
        }
    }
}

fun poison_step(lst, x, y, acc, hit) {
    if (length(lst) == 0) { {acc, hit} }
    else {
        it = hd(lst)
        dx = hd(it) - x
        dy = hd(tl(it)) - y
        if (dx * dx + dy * dy < 0.0020) { poison_step(tl(lst), x, y, [item_at(free_pos(30), 0) | acc], hit + 1) }
        else { poison_step(tl(lst), x, y, [it | acc], hit) }
    }
}

fun items_step(s) {
    f = food_step(g(s, 'food'), g(s, 'x'), g(s, 'y'), [], 0)
    q = poison_step(g(s, 'poison'), g(s, 'x'), g(s, 'y'), [], 0)
    ate = elem(f, 1)
    hit = elem(q, 1)
    s1 = p(p(s, 'food', elem(f, 0)), 'poison', elem(q, 0))
    s2 = if (ate > 0) { add_ev(p(p(s1, 'e', fmin(100.0, g(s1, 'e') + 30.0 * to_float(ate))), 'eaten', g(s1, 'eaten') + ate), 1) } else { s1 }
    if (hit > 0) {
        add_ev(p(p(p(p(s2, 'h', g(s2, 'h') - 15.0 * to_float(hit)), 'e', g(s2, 'e') - 4.0), 'pain', 14), 'poisoned', g(s2, 'poisoned') + hit), 2)
    } else { s2 }
}

# ---- the predator: wander, chase when close, rest after a chase ----
# pred = [x, y, mode, timer, hx, hy]; mode 0 wander, 1 chase, 2 rest
fun pred_step(s) {
    if (g(s, 'pred_on') != 1) { s }
    else {
        pr = g(s, 'pred')
        px = hd(pr)
        py = hd(tl(pr))
        mode = hd(tl(tl(pr)))
        tm = hd(tl(tl(tl(pr))))
        phx = hd(tl(tl(tl(tl(pr)))))
        phy = hd(tl(tl(tl(tl(tl(pr))))))
        dx = g(s, 'x') - px
        dy = g(s, 'y') - py
        d = Math.sqrt(dx * dx + dy * dy) + 0.000001
        alive = g(s, 'dead') == 0
        mode2 = if (mode == 0 && d < 0.5 && alive) { 1 } else { if (mode == 1 && tm <= 0) { 2 } else { if (mode == 2 && tm <= 0) { 0 } else { mode } } }
        tm2 = if (mode2 != mode) { if (mode2 == 1) { 210 } else { if (mode2 == 2) { 90 } else { 120 } } } else { tm - 1 }
        # heading: chase straight at the creature, wander with a slow random turn
        wh = rotate_h(phx, phy, (rndf() - 0.5) * 0.3)
        hx = if (mode2 == 1) { dx / d } else { elem(wh, 0) }
        hy = if (mode2 == 1) { dy / d } else { elem(wh, 1) }
        speed = if (mode2 == 1) { 0.0074 } else { if (mode2 == 0) { 0.0035 } else { 0.0 } }
        nx = clampw(px + hx * speed)
        ny = clampw(py + hy * speed)
        s1 = p(s, 'pred', [nx, ny, mode2, tm2, hx, hy])
        if (mode2 == 1 && d < 0.055 && alive) {
            # a bite: damage, knock the creature back, the predator backs off to rest
            kx = clampw(g(s1, 'x') + dx / d * 0.09)
            ky = clampw(g(s1, 'y') + dy / d * 0.09)
            add_ev(p(p(p(p(p(p(s1, 'h', g(s1, 'h') - 20.0), 'x', kx), 'y', ky), 'pain', 14), 'bitten', g(s1, 'bitten') + 1), 'pred', [nx, ny, 2, 110, hx, hy]), 3)
        } else { s1 }
    }
}

# ---- vitals, death and rebirth ----
fun vitals(s) {
    if (g(s, 'dead') > 0) {
        if (g(s, 'dead') == 1) {
            add_ev(p(p(p(p(p(p(s, 'dead', 0), 'x', 0.5), 'y', 0.5), 'e', 80.0), 'h', 100.0), 'pain', 0), 6)
        } else { p(s, 'dead', g(s, 'dead') - 1) }
    } else {
        regen = if (g(s, 'e') > 50.0 && g(s, 'h') < 100.0) { 0.03 } else { 0.0 }
        s1 = p(p(p(s, 'h', fmin(100.0, g(s, 'h') + regen)), 'life', g(s, 'life') + 1), 'pain', if (g(s, 'pain') > 0) { g(s, 'pain') - 1 } else { 0 })
        starved = g(s1, 'e') <= 0.0
        slain = g(s1, 'h') <= 0.0
        if (starved || slain) {
            add_ev(p(p(p(p(p(s1, 'dead', 70), 'best', if (g(s1, 'life') > g(s1, 'best')) { g(s1, 'life') } else { g(s1, 'best') }), 'life', 0), 'deaths', g(s1, 'deaths') + 1), 'cause', if (slain) { "slain" } else { "starved" }), if (slain) { 5 } else { 4 })
        } else { s1 }
    }
}

# ------------------------------------------------------------
# The world loop
# ------------------------------------------------------------
fun tick_all(tab, i, n) {
    if (i >= n) { 'ok' }
    else {
        t = tget(tab, i)
        if (t == nil) { 'skip' } else { send(t, {'tick'}) }
        tick_all(tab, i + 1, n)
    }
}

fun tick_motors(tab, m, cmd) {
    if (m >= 4) { 'ok' }
    else {
        t = tget(tab, k_motor + m)
        if (t == nil) { 'skip' } else { send(t, {'tick', elem(cmd, m)}) }
        tick_motors(tab, m + 1, cmd)
    }
}

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

fun flag(lst, k) { if (k <= 0) { hd(lst) } else { flag(tl(lst), k - 1) } }

fun world_loop(tab, s) {
    n = num(cget(tab, 'n'))
    want = num(cget(tab, 'want_n'))
    if (want > 0 && want != n) {
        cput(tab, 'want_n', 0)
        rebuild(tab, self(), n, want)
        world_loop(tab, new_world())
    } else {
        if (n == 0) { sleep(20)  world_loop(tab, s) }
        else {
            t0 = timestamp()
            s0 = p(p(s, 'ev', []), 'pred_on', num(cget(tab, 'pred_on')))
            alive = g(s0, 'dead') == 0
            rays = all_rays(s0, 0)
            ids = if (alive) { sensor_ids(s0, rays) } else { [] }
            inject_all(tab, n, ids)
            ex = if (alive) { expert(s0) } else { {0, 0, 0, 0} }
            tick_all(tab, 0, n)
            tick_motors(tab, 0, ex)
            sleep(11)
            got = drain([], [0, 0, 0, 0])
            fired = elem(got, 0)
            mf = elem(got, 1)
            brain_cmd = {flag(mf, 0), flag(mf, 1), flag(mf, 2), flag(mf, 3)}
            # autopilot: the expert drives while the brain is bad, and hands over as it improves
            share = if (num(cget(tab, 'auto')) == 1) { fmax(0.0, fmin(0.85, (0.88 - g(s0, 'acc')) / 0.4)) } else { 0.0 }
            use_expert = alive && rndf() < share
            cmd = if (alive) { if (use_expert) { ex } else { brain_cmd } } else { {0, 0, 0, 0} }
            s1 = if (alive) { vitals(pred_step(items_step(move(s0, cmd)))) } else { vitals(pred_step(s0)) }
            ok = (if (elem(brain_cmd, 0) == elem(ex, 0)) { 1 } else { 0 }) + (if (elem(brain_cmd, 1) == elem(ex, 1)) { 1 } else { 0 }) +
                 (if (elem(brain_cmd, 2) == elem(ex, 2)) { 1 } else { 0 }) + (if (elem(brain_cmd, 3) == elem(ex, 3)) { 1 } else { 0 })
            acc = if (alive) { g(s1, 'acc') * 0.99 + (to_float(ok) / 4.0) * 0.01 } else { g(s1, 'acc') }
            tick = num(cget(tab, 'tick'))
            cput(tab, 'tick', tick + 1)
            cput(tab, 'win_spikes', num(cget(tab, 'win_spikes')) + length(fired))
            if (tick % 40 == 0) {
                cput(tab, 'sps', num(cget(tab, 'win_spikes')))
                cput(tab, 'win_spikes', 0)
                cput(tab, 'topw', top_weights(tab, n))
            } else { 'x' }
            s2 = p(p(s1, 'acc', acc), 'share', share)
            frame(tab, n, tick, fired, mf, ex, rays, s2, if (tick % 40 == 0) { 1 } else { 0 })
            spent = timestamp() - t0
            if (spent < tick_ms) { sleep(tick_ms - spent) } else { 'late' }
            world_loop(tab, s2)
        }
    }
}

fun r3(v) { Math.round(v * 1000) }

fun pts(lst, present_only) {
    if (length(lst) == 0) { [] }
    else {
        it = hd(lst)
        if (present_only == 1 && hd(tl(tl(it))) > 0) { pts(tl(lst), present_only) }
        else { [[r3(hd(it)), r3(hd(tl(it)))] | pts(tl(lst), present_only)] }
    }
}

fun obst_pts(lst) {
    if (length(lst) == 0) { [] }
    else { [[r3(hd(hd(lst))), r3(hd(tl(hd(lst)))), r3(hd(tl(tl(hd(lst)))))] | obst_pts(tl(lst))] }
}

fun ray_pts(lst) {
    if (length(lst) == 0) { [] }
    else { [[r3(hd(hd(lst))), hd(tl(hd(lst)))] | ray_pts(tl(lst))] }
}

fun frame(tab, n, tick, fired, mf, ex, rays, s, with_weights) {
    st = swarm_stats()
    sps = num(cget(tab, 'sps'))
    pr = g(s, 'pred')
    LiveView.broadcast("creature", {'frame', json_encode(%{t: "ev", n: "frame", d: %{
        n: n, tick: tick, s: fired, mo: mf,
        ex: [elem(ex, 0), elem(ex, 1), elem(ex, 2), elem(ex, 3)],
        x: r3(g(s, 'x')), y: r3(g(s, 'y')), hx: r3(g(s, 'hx')), hy: r3(g(s, 'hy')),
        e: Math.round(g(s, 'e')), h: Math.round(g(s, 'h')),
        rays: ray_pts(rays),
        food: pts(g(s, 'food'), 1), poison: pts(g(s, 'poison'), 0),
        pred: [r3(hd(pr)), r3(hd(tl(pr))), hd(tl(tl(pr)))],
        obst: obst_pts(obstacles()),
        dead: g(s, 'dead'), life: g(s, 'life'), best: g(s, 'best'), deaths: g(s, 'deaths'),
        eaten: g(s, 'eaten'), poisoned: g(s, 'poisoned'), bitten: g(s, 'bitten'),
        acc: r3(g(s, 'acc')), share: r3(g(s, 'share')), cause: g(s, 'cause'),
        procs: num(map_get(st, 'processes')), sps: sps, eps: sps * (fan + 4),
        learn: num(cget(tab, 'learn')), lz: num(cget(tab, 'lesioned')), spms: num(cget(tab, 'spawn_ms')),
        pred_on: g(s, 'pred_on'), auto: num(cget(tab, 'auto')), ev: g(s, 'ev'),
        tw: if (with_weights == 1) { list_or_empty(cget(tab, 'topw')) } else { [] }
    }})})
}

fun top_weights(tab, n) {
    app(top_for(tab, n, 0, 0, []), app(top_for(tab, n, 1, 0, []), app(top_for(tab, n, 2, 0, []), top_for(tab, n, 3, 0, []))))
}

fun top_for(tab, n, m, i, acc) {
    if (i >= n) { acc }
    else {
        w = numf(tget(tab, wkey(m, i)))
        if (w > 0.12) { top_for(tab, n, m, i + 1, top_insert(acc, [m, i, Math.round(w * 100)], 14)) }
        else { top_for(tab, n, m, i + 1, acc) }
    }
}

fun top_insert(lst, item, k) {
    merged = insert_sorted(lst, item)
    if (length(merged) > k) { Std.take(merged, k) } else { merged }
}

fun insert_sorted(lst, item) {
    if (length(lst) == 0) { [item] }
    else { if (hd(tl(tl(item))) >= hd(tl(tl(hd(lst))))) { [item | lst] } else { [hd(lst) | insert_sorted(tl(lst), item)] } }
}

# ------------------------------------------------------------
# Commands
# ------------------------------------------------------------
fun inbox(tab) {
    receive {
        {'size', n} ->
            cput(tab, 'want_n', if (n > max_n) { max_n } else { n })
            inbox(tab)
        {'learn'} ->
            cput(tab, 'learn', 1 - num(cget(tab, 'learn')))
            inbox(tab)
        {'pred'} ->
            cput(tab, 'pred_on', 1 - num(cget(tab, 'pred_on')))
            inbox(tab)
        {'auto'} ->
            cput(tab, 'auto', 1 - num(cget(tab, 'auto')))
            inbox(tab)
        {'forget'} ->
            forget(tab, 0, num(cget(tab, 'n')))
            inbox(tab)
        {'lesion', pct} ->
            n = num(cget(tab, 'n'))
            gone = lesion(tab, n * pct / 100, n, [])
            ev("lesions", %{l: Std.take(gone, 2500), n: length(gone)})
            inbox(tab)
        _o -> inbox(tab)
    }
}

fun forget(tab, i, n) {
    if (i >= n) { 'ok' } else { clear_weights(tab, 0, i)  forget(tab, i + 1, n) }
}

fun rndi(n) { Math.floor(rndf() * to_float(n)) }

fun lesion(tab, k, n, acc) {
    if (k <= 0 || n <= 0) { acc }
    else {
        i = rndi(n)
        if (num(cget(tab, 'lesioned')) >= n) { acc }
        else { if (num(tget(tab, k_lesion + i)) == 1) { lesion(tab, k, n, acc) }
        else {
            tput(tab, k_lesion + i, 1)
            t = tget(tab, i)
            if (t == nil) { 'skip' } else { exit_proc(t, 'killed') }
            cput(tab, 'lesioned', num(cget(tab, 'lesioned')) + 1)
            lesion(tab, k - 1, n, [i | acc])
        }}
    }
}

fun ev(name, data) {
    LiveView.broadcast("creature", {'frame', json_encode(%{t: "ev", n: name, d: data})})
}

fun inbox_send(msg) {
    a = whereis('creature_in')
    if (a == nil) { 'noop' } else { send(a, msg) }
}

# ------------------------------------------------------------
# View — static shell; motion is in creature.js
# ------------------------------------------------------------
fun mount(params) {
    if (LiveView.connected(params) == 'true') { LiveView.subscribe("creature") } else { 'noop' }
    %{}
}

fun stat(id, label) {
    "<div class=\"card stat\"><div class=\"lbl\">" ++ label ++ "</div><div class=\"val\" id=\"v-" ++ id ++ "\">&ndash;</div>" ++
    "<div class=\"chip\" id=\"d-" ++ id ++ "\"></div></div>"
}

fun css() {
    "<style>" ++
    ":root{--bg:#000;--card:#0a0a0a;--line:#1f1f1f;--line2:#2e2e2e;--tx:#ededed;--mu:#8f8f8f;--blue:#3b9eff;--red:#ff4d4d;--green:#50e3c2;--amber:#f5a623}" ++
    "*{box-sizing:border-box}html,body{height:100%;background:var(--bg);color:var(--tx);margin:0}" ++
    "body{font-family:ui-sans-serif,-apple-system,'SF Pro Text',Inter,'Segoe UI',sans-serif;-webkit-font-smoothing:antialiased;overflow:hidden}" ++
    "#live-root{height:100%;display:flex;flex-direction:column}" ++
    ".nav{height:56px;flex:none;display:flex;align-items:center;gap:14px;padding:0 24px;border-bottom:1px solid var(--line)}" ++
    ".logo{display:flex;align-items:center;gap:10px;font-weight:600;font-size:14px}.crumb{color:var(--mu);font-size:14px}.crumb:before{content:'/';margin-right:14px;color:#3a3a3a}" ++
    ".live{margin-left:auto;display:flex;align-items:center;gap:8px;font-size:12px;color:var(--mu);padding:5px 11px;border:1px solid var(--line2);border-radius:99px}" ++
    ".dot{width:7px;height:7px;border-radius:50%;background:var(--green);animation:pulse 1.8s infinite}" ++
    "@keyframes pulse{70%{box-shadow:0 0 0 7px rgba(80,227,194,0)}100%{box-shadow:0 0 0 0 rgba(80,227,194,0)}}" ++
    ".main{flex:1;min-height:0;padding:18px 24px 22px;display:flex;flex-direction:column;gap:14px}" ++
    ".cards{display:grid;grid-template-columns:repeat(6,1fr);gap:12px;flex:none}" ++
    ".card{background:var(--card);border:1px solid var(--line);border-radius:12px}" ++
    ".stat{padding:12px 14px;height:88px}.lbl{font-size:11.5px;color:var(--mu)}" ++
    ".val{font-size:26px;font-weight:600;letter-spacing:-.03em;font-variant-numeric:tabular-nums;margin-top:2px}" ++
    ".chip{font-size:10.5px;color:var(--mu);margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.chip.up{color:var(--green)}.chip.bad{color:var(--red)}.chip.warn{color:var(--amber)}" ++
    ".body{flex:1;min-height:0;display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr) 300px;gap:14px}" ++
    ".pane{position:relative;overflow:hidden;background:#040406;min-height:0}.pane canvas{position:absolute;inset:0}" ++
    ".ph{position:absolute;top:12px;left:14px;font-size:12px;color:var(--mu);pointer-events:none}.ph b{color:var(--tx)}" ++
    ".bars{position:absolute;left:14px;bottom:12px;right:14px;display:grid;grid-template-columns:1fr 1fr;gap:10px;pointer-events:none}" ++
    ".bar{height:7px;border-radius:4px;background:#14161a;overflow:hidden}.bar i{display:block;height:100%;width:0;border-radius:4px;transition:width .1s}" ++
    ".bl{font-size:10.5px;color:var(--mu);margin-bottom:3px;display:flex;justify-content:space-between}" ++
    ".col{display:flex;flex-direction:column;gap:12px;min-height:0;overflow:auto}" ++
    ".col .card{padding:12px 14px;flex:none}.col h3{font-size:12px;font-weight:600;margin:0 0 9px;display:flex;justify-content:space-between}.col h3 span{color:var(--mu);font-weight:400}" ++
    "#chart-cv{width:100%;height:70px;display:block}" ++
    "#log{font:11.5px/1.55 ui-sans-serif,-apple-system,sans-serif;height:150px;overflow:hidden}" ++
    ".ev{display:flex;gap:8px;padding:2px 0;animation:in .3s ease}.ev i{width:6px;height:6px;border-radius:50%;margin-top:6px;flex:none}.ev time{margin-left:auto;color:#666;font-size:10px}" ++
    "@keyframes in{from{opacity:0;transform:translateY(-5px)}to{opacity:1;transform:none}}" ++
    ".seg{display:flex;gap:2px;background:#111;border:1px solid var(--line);border-radius:8px;padding:2px;margin-bottom:9px}" ++
    ".seg button{flex:1;font:inherit;font-size:11px;color:var(--mu);background:transparent;border:0;border-radius:6px;padding:6px 3px;cursor:pointer}" ++
    ".seg button:hover{color:var(--tx)}.seg button.on{background:#232323;color:var(--tx)}" ++
    ".row2{display:flex;gap:7px;margin-bottom:7px}.btn{flex:1;font:inherit;font-size:11.5px;font-weight:500;color:var(--tx);background:#111;border:1px solid var(--line2);border-radius:8px;padding:7px 8px;cursor:pointer}" ++
    ".btn:hover{background:#1a1a1a;border-color:#444}.btn.on{background:#e6e6e6;color:#06070a;border-color:#e6e6e6}" ++
    ".btn.danger{color:#ff9a9a;border-color:#5b2020;background:#1a0b0b}.btn.danger:hover{background:#2a1010;border-color:var(--red)}" ++
    ".how{font-size:11.5px;color:var(--mu);line-height:1.55;margin:0}.how b{color:var(--tx);font-weight:600}" ++
    "@media(max-width:1180px){.cards{grid-template-columns:repeat(3,1fr)}.body{grid-template-columns:1fr}body{overflow:auto}#live-root{height:auto}.pane{height:520px}}" ++
    "</style>"
}

fun render(assigns) {
    LiveView.h(
        css() ++
        "<header class=\"nav\"><div class=\"logo\">" ++
        "<svg width=\"22\" height=\"22\" viewBox=\"0 0 22 22\"><circle cx=\"11\" cy=\"11\" r=\"4\" fill=\"#ededed\"/><path d=\"M11 2v5M11 15v5M2 11h5M15 11h5\" stroke=\"#555\" stroke-width=\"1.5\"/></svg>" ++
        "Creature</div><span class=\"crumb\">a body, senses and a brain of processes</span>" ++
        "<div class=\"live\"><span class=\"dot\"></span>live &middot; <span id=\"o-fps\">0</span> fps</div></header>" ++
        "<div class=\"main\"><div class=\"cards\">" ++
        stat("procs", "Neurons (processes)") ++ stat("sps", "Spikes / s") ++ stat("acc", "Brain vs expert") ++
        stat("life", "Survival (this life)") ++ stat("eat", "Food eaten") ++ stat("hurt", "Poison / bites") ++
        "</div><div class=\"body\">" ++
        "<div class=\"card pane\" id=\"arena\"><canvas id=\"arena-cv\" sw-keep></canvas><div class=\"ph\" id=\"ah\" sw-keep>the world</div>" ++
        "<div class=\"bars\"><div><div class=\"bl\"><span>energy</span><span id=\"t-e\">100</span></div><div class=\"bar\"><i id=\"b-e\" style=\"background:#50e3c2\"></i></div></div>" ++
        "<div><div class=\"bl\"><span>health</span><span id=\"t-h\">100</span></div><div class=\"bar\"><i id=\"b-h\" style=\"background:#ff6b6b\"></i></div></div></div></div>" ++
        "<div class=\"card pane\" id=\"brain\"><canvas id=\"brain-cv\" sw-keep></canvas><div class=\"ph\" id=\"bh\" sw-keep>the brain</div></div>" ++
        "<div class=\"col\">" ++
        "<div class=\"card\"><h3>Brain vs expert <span id=\"h-acc\">accuracy</span></h3><canvas id=\"chart-cv\" sw-keep></canvas>" ++
        "<p class=\"how\" id=\"h-auto\" style=\"margin-top:6px\">autopilot</p></div>" ++
        "<div class=\"card\"><h3>Activity</h3><div id=\"log\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Brain size</h3><div class=\"seg\">" ++
        "<button data-size=\"1200\">1.2k</button><button data-size=\"2400\">2.4k</button><button data-size=\"3600\">3.6k</button><button data-size=\"4800\">4.8k</button></div>" ++
        "<h3>Experiments</h3><div class=\"row2\"><button class=\"btn on\" id=\"b-learn\">Plasticity: on</button><button class=\"btn\" id=\"b-forget\">Forget</button></div>" ++
        "<div class=\"row2\"><button class=\"btn danger\" data-lesion=\"10\">Lesion 10%</button><button class=\"btn danger\" data-lesion=\"30\">Lesion 30%</button></div>" ++
        "<div class=\"row2\"><button class=\"btn on\" id=\"b-auto\">Autopilot: on</button><button class=\"btn on\" id=\"b-pred\">Predator: on</button></div></div>" ++
        "<div class=\"card\"><h3>How it works</h3><p class=\"how\">Every neuron is a <b>process</b> that spikes by messaging its neighbours. The creature <b>sees</b> with 7 rays, <b>smells</b> food and poison, feels <b>pain</b>, and senses hunger and health. Only the readout into the four motor neurons learns, and it learns by <b>copying a hand-written expert</b> (imitation, not reinforcement). While the brain is bad the expert <b>autopilots</b>; it hands over as accuracy rises. Switch Autopilot off to watch the brain drive alone.</p></div>" ++
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
    } else { if (name == "pred") {
        inbox_send({'pred'})
    } else { if (name == "auto") {
        inbox_send({'auto'})
    } else { if (name == "lesion") {
        inbox_send({'lesion', to_int(map_get(value, 'p'))})
    } else { 'noop' }}}}}}
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
    cput(tab, 'pred_on', 1)
    cput(tab, 'auto', 1)
    start_sups(tab, 0)
    world = spawn(world_loop(tab, new_world()))
    register('creature_world', world)
    register('creature_in', spawn(inbox(tab)))
    start_motors(tab, world, 0)
    cput(tab, 'want_n', 2400)
    LiveView.start(4013, [
        {"/", %{
            title: "Creature",
            js: CreatureJs.js(),
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
