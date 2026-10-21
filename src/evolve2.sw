module Main

# swarm-live — Evolution
#
#   make bin/evolve && scripts/run.sh evolve      ->  http://localhost:4014
#
# A population of creatures lives in one arena with food, poison, obstacles and a
# predator. EVERY CREATURE HAS ITS OWN BRAIN: its own supervised swarm of neuron
# processes. A birth spawns a new brain (a few hundred processes); a death stops
# it. Nobody picks the winners. Whoever starves or is eaten disappears; whoever
# has spare energy reproduces.
#
#   GENES      speed, vision range, brain size (number of neuron processes), caution
#              and hunger threshold. Each has a metabolic cost, so there are trade-offs:
#              fast bodies, long sight and big brains all burn energy.
#   BIRTH      a creature with surplus energy (and a cool-down) has a child: genes are
#              inherited with mutation, the child starts with some of the parent's
#              energy and, when its brain is the same size, inherits the parent's
#              learned readout (imprinting) so it does not start from scratch.
#   LEARNING   inside a lifetime the readout into the motor neurons learns by copying a
#              built-in expert (imitation, as in Creature). The genes shape the expert
#              (caution, hunger) and the body, so selection acts on temperament and
#              build, not on the learning rule.
#
# This is neuroevolution of traits plus imitation learning, not a claim of open-ended
# evolution: the readout is inherited, not evolved.

import LiveView
import Evolve2Js
import Math
import Std

let max_slots = 24
let maxm = 240
let tick_ms = 25
let fan = 8
let sensor_fan = 22

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
fun clampf(v, lo, hi) { if (v < lo) { lo } else { if (v > hi) { hi } else { v } } }
fun g(s, k) { map_get(s, k) }
fun p(s, k, v) { map_put(s, k, v) }
fun app(a, b) { if (length(a) == 0) { b } else { [hd(a) | app(tl(a), b)] } }

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

fun rndi(n) { Math.floor(rndf() * to_float(n)) }
fun gauss() { (rndf() + rndf() + rndf() - 1.5) * 1.15 }

# ------------------------------------------------------------
# Neurons and motor neurons are processes. Ids are global:
# gid = slot * 450 + local, so every creature owns a block of ids.
# ------------------------------------------------------------
fun neuron(slot, i, m, tab, world) {
    tput(tab, slot * maxm + i, self())
    neuron_loop(slot, i, m, tab, world, 0.0, 0)
}

fun neuron_loop(slot, i, m, tab, world, v, refr) {
    receive {
        {'s', w} -> neuron_loop(slot, i, m, tab, world, v + w, refr)
        {'tick'} ->
            v2 = v * 0.86
            if (v2 >= 1.0 && refr <= 0) {
                fire(slot, i, m, tab, 0)
                send(world, {'f', slot * maxm + i})
                neuron_loop(slot, i, m, tab, world, 0.0, 2)
            } else {
                neuron_loop(slot, i, m, tab, world, v2, if (refr > 0) { refr - 1 } else { 0 })
            }
        {'stop'} -> 'ok'
    }
}

# region 0 visual, 1 chemical, 2 association, per creature
fun fire(slot, i, m, tab, k) {
    if (k >= fan) { fire_motors(slot, tab, i, 0) }
    else {
        sz = m / 3
        r = i / sz
        tr = if (k < 4 || r >= 2 || k >= 6) { if (r > 2) { 2 } else { r } } else { 2 }
        t = tget(tab, slot * maxm + tr * sz + hsh(i, k) % sz)
        if (t == nil) { 'skip' } else { send(t, {'s', if (k < 6) { 0.5 } else { 0.0 - 0.9 }}) }
        fire(slot, i, m, tab, k + 1)
    }
}

fun fire_motors(slot, tab, i, mi) {
    if (mi >= 4) { 'ok' }
    else {
        t = tget(tab, k_motor + slot * 4 + mi)
        if (t == nil) { 'skip' } else { send(t, {'r', i}) }
        fire_motors(slot, tab, i, mi + 1)
    }
}

fun wkey(slot, mi, i) { k_weight + (slot * 4 + mi) * 1000 + i }

fun motor(slot, mi, tab, world) {
    tput(tab, k_motor + slot * 4 + mi, self())
    motor_loop(slot, mi, tab, world, 0.0, 0, [])
}

fun motor_loop(slot, mi, tab, world, y, cnt, recs) {
    receive {
        {'r', i} ->
            w = numf(tget(tab, wkey(slot, mi, i)))
            motor_loop(slot, mi, tab, world, y + w, cnt + 1, [{i, w} | recs])
        {'tick', t} ->
            target = if (t == 1) { 1.4 } else { 0.0 }
            if (num(cget(tab, 'learn')) == 1 && cnt > 0) {
                adjust(tab, slot, mi, recs, 0.09 * (target - y) / to_float(cnt))
            } else { 'frozen' }
            if (y >= 0.7) { send(world, {'m', slot, mi}) } else { 'quiet' }
            motor_loop(slot, mi, tab, world, 0.0, 0, [])
    }
}

fun adjust(tab, slot, mi, recs, step) {
    if (length(recs) == 0) { 'ok' }
    else {
        r = hd(recs)
        w = elem(r, 1) + step
        tput(tab, wkey(slot, mi, elem(r, 0)), if (w > 2.0) { 2.0 } else { if (w < 0.0 - 2.0) { 0.0 - 2.0 } else { w } })
        adjust(tab, slot, mi, tl(recs), step)
    }
}

# ------------------------------------------------------------
# A brain's life cycle: spawn, copy weights, stop
# ------------------------------------------------------------
fun spawn_brain(tab, slot, m, world, i) {
    if (i >= m) { 'ok' }
    else {
        sup = cget(tab, k_sup + slot)
        sup_start_child(sup, {nil, fun() { neuron(slot, i, m, tab, world) }, 'transient'})
        spawn_brain(tab, slot, m, world, i + 1)
    }
}

fun wait_brain(tab, slot, i, m, deadline) {
    if (i >= m) { 'ok' }
    else {
        if (tget(tab, slot * maxm + i) == nil && timestamp() < deadline) { sleep(1)  wait_brain(tab, slot, i, m, deadline) }
        else { wait_brain(tab, slot, i + 1, m, deadline) }
    }
}

fun kill_brain(tab, slot, i, m) {
    if (i >= m) { 'ok' }
    else {
        t = tget(tab, slot * maxm + i)
        if (t == nil) { 'skip' } else { send(t, {'stop'}) }
        ets_delete(tab + (slot * maxm + i) % 16, slot * maxm + i)
        clear_w(tab, slot, 0, i)
        kill_brain(tab, slot, i + 1, m)
    }
}

fun clear_w(tab, slot, mi, i) {
    if (mi >= 4) { 'ok' } else { ets_delete(tab + wkey(slot, mi, i) % 16, wkey(slot, mi, i))  clear_w(tab, slot, mi + 1, i) }
}

fun copy_w(tab, from, to, i, m) {
    if (i >= m) { 'ok' }
    else { copy_one(tab, from, to, 0, i)  copy_w(tab, from, to, i + 1, m) }
}

fun copy_one(tab, from, to, mi, i) {
    if (mi >= 4) { 'ok' }
    else {
        w = tget(tab, wkey(from, mi, i))
        if (w == nil) { 'none' } else { tput(tab, wkey(to, mi, i), w) }
        copy_one(tab, from, to, mi + 1, i)
    }
}

# ------------------------------------------------------------
# The world (shared items) and genomes
# ------------------------------------------------------------
fun obstacles() { [[0.30, 0.35, 0.07], [0.70, 0.28, 0.06], [0.55, 0.72, 0.08], [0.18, 0.74, 0.06], [0.86, 0.80, 0.05], [0.12, 0.20, 0.04], [0.90, 0.50, 0.05]] }

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

fun free_pos(tries) {
    x = 0.06 + rndf() * 0.88
    y = 0.06 + rndf() * 0.88
    if (tries <= 0 || in_obstacle(x, y, 0.04, obstacles()) == 'false') { [x, y] } else { free_pos(tries - 1) }
}

fun item_at(pos, regrow) { [hd(pos), hd(tl(pos)), regrow] }
fun init_items(k, regrow) { if (k <= 0) { [] } else { [item_at(free_pos(30), regrow) | init_items(k - 1, regrow)] } }

fun random_genome() {
    %{speed: 0.8 + rndf() * 0.6, vis: 0.28 + rndf() * 0.25, m: 3 * (20 + rndi(40)),
      caution: 0.7 + rndf() * 0.7, hunger: 60.0 + rndf() * 30.0,
      atk: 0.4 + rndf() * 0.8, arm: rndf() * 0.8, size: 0.85 + rndf() * 0.3, aggr: rndf() * 0.6, mut: 0.8 + rndf() * 0.6}
}

# one gene: a small Gaussian step scaled by the creature's own mutation-rate gene,
# and a rare big jump (a fresh random value) so the pool keeps discovering new bodies
fun mut_gene(v, lo, hi, sd, rate) {
    if (rndf() < 0.03 * rate) { lo + rndf() * (hi - lo) }
    else { clampf(v + (hi - lo) * sd * rate * gauss(), lo, hi) }
}

fun mutate(gn) {
    rt = g(gn, 'mut')
    dm = if (rndf() < 0.20 * rt) { if (rndf() < 0.5) { 30 } else { 0 - 30 } } else { 0 }
    m0 = g(gn, 'm') + dm
    %{speed: mut_gene(g(gn, 'speed'), 0.6, 1.8, 0.07, rt),
      vis: mut_gene(g(gn, 'vis'), 0.2, 0.6, 0.07, rt),
      m: if (m0 < 60) { 60 } else { if (m0 > 240) { 240 } else { m0 } },
      caution: mut_gene(g(gn, 'caution'), 0.4, 1.8, 0.08, rt),
      hunger: mut_gene(g(gn, 'hunger'), 40.0, 98.0, 0.05, rt),
      atk: mut_gene(g(gn, 'atk'), 0.2, 2.2, 0.08, rt),
      arm: mut_gene(g(gn, 'arm'), 0.0, 1.6, 0.08, rt),
      size: mut_gene(g(gn, 'size'), 0.7, 1.5, 0.05, rt),
      aggr: mut_gene(g(gn, 'aggr'), 0.0, 1.0, 0.08, rt),
      mut: mut_gene(g(gn, 'mut'), 0.4, 2.6, 0.06, 1.0)}
}

fun genome_of(c) {
    %{speed: g(c, 'speed'), vis: g(c, 'vis'), m: g(c, 'm'), caution: g(c, 'caution'), hunger: g(c, 'hunger'),
      atk: g(c, 'atk'), arm: g(c, 'arm'), size: g(c, 'size'), aggr: g(c, 'aggr'), mut: g(c, 'mut')}
}

fun new_creature(id, slot, gen, par, hue, gn, x, y, e) {
    %{id: id, slot: slot, gen: gen, par: par, hue: hue,
      speed: g(gn, 'speed'), vis: g(gn, 'vis'), m: g(gn, 'm'), caution: g(gn, 'caution'), hunger: g(gn, 'hunger'),
      atk: g(gn, 'atk'), arm: g(gn, 'arm'), size: g(gn, 'size'), aggr: g(gn, 'aggr'), mut: g(gn, 'mut'),
      x: x, y: y, hx: 1.0, hy: 0.0, e: e, h: 100.0, pain: 0, bump: 0, age: 0, cool: 300, acd: 0, by: 0, kills: 0,
      eaten: 0, poisoned: 0, bitten: 0, acc: 0.5, share: 0.85, ev: []}
}

fun new_world() {
    %{food: init_items(16, 0), poison: init_items(10, 0),
      preds: [[0.90, 0.90, 0, 80, 0.0 - 1.0, 0.0], [0.10, 0.88, 0, 140, 1.0, 0.0]],
      crs: [], next_id: 1, init: 0, pred_on: 1, births: 0, deaths: 0, starved: 0, slain: 0, devoured: 0,
      maxgen: 0, record: 0, evs: [], tick: 0}
}

# ---- vision (range comes from the creature's gene) ----
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
    b0 = {wall_t(x, y, dx, dy), 3}
    b1 = cast_obst(obstacles(), x, y, dx, dy, b0)
    b2 = cast_items(g(s, 'food'), 0, 0.025, x, y, dx, dy, b1, 1)
    b3 = cast_items(g(s, 'poison'), 1, 0.03, x, y, dx, dy, b2, 0)
    b4 = cast_items(g(s, 'oth'), 4, 0.03, x, y, dx, dy, b3, 0)
    cast_items(g(s, 'preds'), 2, 0.04, x, y, dx, dy, b4, 0)
}

fun all_rays(s, k) { if (k >= 7) { [] } else { [cast_pair(s, k) | all_rays(s, k + 1)] } }
fun cast_pair(s, k) { r = cast(s, k)  [elem(r, 0), elem(r, 1)] }

fun ray_sensor(k, r, vis) {
    t = hd(r)
    if (t > vis) { -1 } else { k * 15 + hd(tl(r)) * 3 + (if (t < 0.27 * vis) { 0 } else { if (t < 0.62 * vis) { 1 } else { 2 } }) }
}

fun vision_ids(rays, k, vis) {
    if (length(rays) == 0) { [] }
    else {
        id = ray_sensor(k, hd(rays), vis)
        if (id < 0) { vision_ids(tl(rays), k + 1, vis) } else { [id | vision_ids(tl(rays), k + 1, vis)] }
    }
}

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

fun smell_one(base, c, acc) {
    lv = Math.floor(fmin(3.0, c * 2.0))
    if (lv >= 1) { [base + lv - 1 | acc] } else { acc }
}

fun smell_ids(s) {
    x = g(s, 'x')
    y = g(s, 'y')
    hx = g(s, 'hx')
    hy = g(s, 'hy')
    lx = x + 0.03 * (hx * 0.766 - hy * 0.643)
    ly = y + 0.03 * (hx * 0.643 + hy * 0.766)
    rx = x + 0.03 * (hx * 0.766 + hy * 0.643)
    ry = y + 0.03 * (0.0 - hx * 0.643 + hy * 0.766)
    ids0 = smell_one(105, conc(g(s, 'food'), lx, ly, 1, 0.0), [])
    ids1 = smell_one(108, conc(g(s, 'food'), rx, ry, 1, 0.0), ids0)
    ids2 = smell_one(111, conc(g(s, 'poison'), lx, ly, 0, 0.0), ids1)
    smell_one(114, conc(g(s, 'poison'), rx, ry, 0, 0.0), ids2)
}

fun bin4(v) { if (v < 25.0) { 0 } else { if (v < 50.0) { 1 } else { if (v < 75.0) { 2 } else { 3 } } } }

fun body_ids(s) {
    a = if (g(s, 'pain') > 0) { [117] } else { [] }
    b = if (g(s, 'bump') > 0) { [118 | a] } else { a }
    [119 + bin4(g(s, 'e')), 123 + bin4(g(s, 'h')) | b]
}

fun sensor_ids(s, rays) { app(vision_ids(rays, 0, g(s, 'vis')), app(smell_ids(s), body_ids(s))) }

fun inject_all(tab, slot, m, ids) {
    if (length(ids) == 0) { 'ok' }
    else { inject(tab, slot, m, hd(ids), 0)  inject_all(tab, slot, m, tl(ids)) }
}

fun inject(tab, slot, m, sid, k) {
    if (k >= sensor_fan) { 'ok' }
    else {
        sz = m / 3
        region = if (sid < 105) { 0 } else { 1 }
        t = tget(tab, slot * maxm + region * sz + hsh(1000 + sid, k) % sz)
        if (t == nil) { 'skip' } else { send(t, {'s', 0.75}) }
        inject(tab, slot, m, sid, k + 1)
    }
}

# ---- the expert; the genes (caution, hunger) shape its temperament ----
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

fun steer(hx, hy, dx, dy) {
    len = Math.sqrt(dx * dx + dy * dy) + 0.000001
    cross = (hx * dy - hy * dx) / len
    dot = (hx * dx + hy * dy) / len
    pos = if (cross > 0.12 || (dot < 0.0 && cross >= 0.0)) { 1 } else { 0 }
    neg = if (cross < 0.0 - 0.12 || (dot < 0.0 && cross < 0.0)) { 1 } else { 0 }
    {pos, neg, if (dot > 0.0 - 0.2) { 1 } else { 0 }}
}

fun hue_gap(a, b) {
    d = (a - b + 720) % 360
    if (d > 180) { 360 - d } else { d }
}

fun nearest_pred(lst, x, y, best) {
    if (length(lst) == 0) { best }
    else {
        pr = hd(lst)
        dx = x - hd(pr)
        dy = y - hd(tl(pr))
        d = Math.sqrt(dx * dx + dy * dy)
        nearer = hd(tl(tl(pr))) != 2 && (best == nil || d < hd(best))
        nearest_pred(tl(lst), x, y, if (nearer) { [d, dx, dy] } else { best })
    }
}

# other creatures are [x, y, hue, aggr*100, id]; kin (similar hue) are ignored.
# want_aggr = 1 -> only aggressive strangers (a bully), 0 -> any stranger (prey). Returns [d, dx, dy] towards it.
fun nearest_other(lst, x, y, hue, want_aggr, maxd, best) {
    if (length(lst) == 0) { best }
    else {
        o = hd(lst)
        dx = hd(o) - x
        dy = hd(tl(o)) - y
        d = Math.sqrt(dx * dx + dy * dy)
        stranger = hue_gap(hue, hd(tl(tl(o)))) >= 25
        ok = stranger && d < maxd && (want_aggr == 0 || hd(tl(tl(tl(o)))) >= 50)
        nearest_other(tl(lst), x, y, hue, want_aggr, maxd, if (ok && (best == nil || d < hd(best))) { [d, dx, dy] } else { best })
    }
}

fun expert(s) {
    x = g(s, 'x')
    y = g(s, 'y')
    hx = g(s, 'hx')
    hy = g(s, 'hy')
    cau = g(s, 'caution')
    hue = g(s, 'hue')
    np = if (g(s, 'pred_on') == 1) { nearest_pred(g(s, 'preds'), x, y, nil) } else { nil }
    thr = if (np != nil && hd(np) < 0.30 * cau) { np } else { nil }
    bully = nearest_other(g(s, 'oth'), x, y, hue, 1, 0.14 * cau, nil)
    poi = nearest_hazard(g(s, 'poison'), 0.03, x, y, hx, hy, nil)
    haz = obst_as_hazards(obstacles(), x, y, hx, hy, poi)
    wall = x < 0.07 || x > 0.93 || y < 0.07 || y > 0.93
    hungry_hunter = g(s, 'aggr') >= 0.5 && g(s, 'e') < g(s, 'hunger') + 25.0
    prey = if (hungry_hunter) { nearest_other(g(s, 'oth'), x, y, hue, 0, 0.24, nil) } else { nil }
    if (thr != nil) {
        pd = hd(thr)
        pdx = hd(tl(thr))
        pdy = hd(tl(tl(thr)))
        wd = fmin(fmin(x, 1.0 - x), fmin(y, 1.0 - y))
        wf = if (wd < 0.22) { 1.6 * (0.22 - wd) / 0.22 } else { 0.0 }
        cl = Math.sqrt((0.5 - x) * (0.5 - x) + (0.5 - y) * (0.5 - y)) + 0.000001
        st = steer(hx, hy, pdx / (pd + 0.000001) + (0.5 - x) / cl * wf, pdy / (pd + 0.000001) + (0.5 - y) / cl * wf)
        {elem(st, 2), elem(st, 0), elem(st, 1), if (pd < 0.22 * cau) { 1 } else { 0 }}
    } else { if (bully != nil) {
        st = steer(hx, hy, 0.0 - hd(tl(bully)), 0.0 - hd(tl(tl(bully))))
        {elem(st, 2), elem(st, 0), elem(st, 1), if (hd(bully) < 0.10) { 1 } else { 0 }}
    } else { if (haz != nil) {
        st = steer(hx, hy, 0.0 - hd(tl(haz)), 0.0 - hd(tl(tl(haz))))
        {if (hd(haz) < 0.03) { 0 } else { elem(st, 2) }, elem(st, 0), elem(st, 1), 0}
    } else { if (wall) {
        st = steer(hx, hy, 0.5 - x, 0.5 - y)
        {elem(st, 2), elem(st, 0), elem(st, 1), 0}
    } else { if (prey != nil) {
        st = steer(hx, hy, hd(tl(prey)), hd(tl(tl(prey))))
        {elem(st, 2), elem(st, 0), elem(st, 1), if (hd(prey) < 0.10) { 1 } else { 0 }}
    } else {
        food = nearest_food(g(s, 'food'), x, y, nil)
        if (food != nil && g(s, 'e') < g(s, 'hunger')) {
            st = steer(hx, hy, hd(tl(food)), hd(tl(tl(food))))
            {elem(st, 2), elem(st, 0), elem(st, 1), 0}
        } else {
            r = rndf()
            {1, if (r < 0.06) { 1 } else { 0 }, if (r > 0.94) { 1 } else { 0 }, 0}
        }
    }}}}}
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

# cmd = {fwd, turn+, turn-, boost}; the speed gene scales the whole gait
fun move(c, cmd) {
    ang = 0.11 * to_float(elem(cmd, 1) - elem(cmd, 2))
    hh = rotate_h(g(c, 'hx'), g(c, 'hy'), ang)
    sg = g(c, 'speed') / (1.0 + 0.18 * g(c, 'arm'))
    speed = if (elem(cmd, 0) == 1) { if (elem(cmd, 3) == 1) { 0.0175 * sg } else { 0.0100 * sg } } else { 0.0 }
    nx = g(c, 'x') + elem(hh, 0) * speed
    ny = g(c, 'y') + elem(hh, 1) * speed
    po = push_out(nx, ny, obstacles())
    cx = clampw(elem(po, 0))
    cy = clampw(elem(po, 1))
    bumped = if (elem(po, 2) == 1 || cx != elem(po, 0) || cy != elem(po, 1)) { 1 } else { 0 }
    cost = speed * 1.5 + (if (elem(cmd, 3) == 1 && elem(cmd, 0) == 1) { 0.05 } else { 0.0 })
    p(p(p(p(p(p(c, 'x', cx), 'y', cy), 'hx', elem(hh, 0)), 'hy', elem(hh, 1)), 'bump', bumped), 'e', g(c, 'e') - cost)
}

fun add_ev(c, code) { p(c, 'ev', [code | g(c, 'ev')]) }

fun food_step(lst, x, y, r2, acc, ate) {
    if (length(lst) == 0) { {acc, ate} }
    else {
        it = hd(lst)
        t = hd(tl(tl(it)))
        if (t > 0) {
            if (t == 1) { food_step(tl(lst), x, y, r2, [item_at(free_pos(30), 0) | acc], ate) }
            else { food_step(tl(lst), x, y, r2, [[hd(it), hd(tl(it)), t - 1] | acc], ate) }
        } else {
            dx = hd(it) - x
            dy = hd(tl(it)) - y
            if (dx * dx + dy * dy < r2) { food_step(tl(lst), x, y, r2, [[hd(it), hd(tl(it)), 180] | acc], ate + 1) }
            else { food_step(tl(lst), x, y, r2, [it | acc], ate) }
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

# one creature touches the shared items: returns {creature, food, poison}
fun items_step(c, food, poison) {
    f = food_step(food, g(c, 'x'), g(c, 'y'), 0.0016 * g(c, 'size') * g(c, 'size'), [], 0)
    q = poison_step(poison, g(c, 'x'), g(c, 'y'), [], 0)
    ate = elem(f, 1)
    hit = elem(q, 1)
    c1 = if (ate > 0) { add_ev(p(p(c, 'e', fmin(100.0, g(c, 'e') + 30.0 * to_float(ate))), 'eaten', g(c, 'eaten') + ate), 1) } else { c }
    c2 = if (hit > 0) { add_ev(p(p(p(p(c1, 'h', g(c1, 'h') - 15.0 * to_float(hit)), 'e', g(c1, 'e') - 4.0), 'pain', 14), 'poisoned', g(c1, 'poisoned') + hit), 2) } else { c1 }
    {c2, elem(f, 0), elem(q, 0)}
}

# ---- predators hunt the nearest creature, but fairly: stalk (a visible warning), a short chase
# that is slower than a boosting creature, then a long rest ----
fun nearest_creature(crs, px, py, best) {
    if (length(crs) == 0) { best }
    else {
        c = hd(crs)
        dx = g(c, 'x') - px
        dy = g(c, 'y') - py
        d = Math.sqrt(dx * dx + dy * dy)
        nearest_creature(tl(crs), px, py, if (best == nil || d < hd(best)) { [d, g(c, 'id'), dx, dy] } else { best })
    }
}

fun bite_creature(crs, id, kx, ky) {
    if (length(crs) == 0) { [] }
    else {
        c = hd(crs)
        if (g(c, 'id') == id) {
            dmg = 24.0 / (1.0 + 0.9 * g(c, 'arm'))
            [add_ev(p(p(p(p(p(p(c, 'h', g(c, 'h') - dmg), 'x', clampw(g(c, 'x') + kx)), 'y', clampw(g(c, 'y') + ky)), 'pain', 14), 'bitten', g(c, 'bitten') + 1), 'by', 0), 3) | tl(crs)]
        } else { [c | bite_creature(tl(crs), id, kx, ky)] }
    }
}

# pred = [x, y, mode, timer, hx, hy]; mode 0 wander, 3 stalk (warning), 1 chase, 2 rest. Returns {world, pred}
fun pred_one(s, pr) {
    px = hd(pr)
    py = hd(tl(pr))
    mode = hd(tl(tl(pr)))
    tm = hd(tl(tl(tl(pr))))
    phx = hd(tl(tl(tl(tl(pr)))))
    phy = hd(tl(tl(tl(tl(tl(pr))))))
    tg = nearest_creature(g(s, 'crs'), px, py, nil)
    d = if (tg == nil) { 9.0 } else { hd(tg) + 0.000001 }
    dx = if (tg == nil) { 0.0 } else { hd(tl(tl(tg))) }
    dy = if (tg == nil) { 0.0 } else { hd(tl(tl(tl(tg)))) }
    mode2 = if (mode == 0) { if (d < 0.32) { 3 } else { 0 } }
            else { if (mode == 3) { if (tm <= 0) { if (d < 0.42) { 1 } else { 0 } } else { 3 } }
            else { if (mode == 1) { if (tm <= 0 || tg == nil || d > 0.5) { 2 } else { 1 } }
            else { if (tm <= 0) { 0 } else { 2 } } } }
    tm2 = if (mode2 != mode) { if (mode2 == 3) { 60 } else { if (mode2 == 1) { 120 } else { if (mode2 == 2) { 150 } else { 100 } } } } else { tm - 1 }
    wh = rotate_h(phx, phy, (rndf() - 0.5) * 0.3)
    face = (mode2 == 1 || mode2 == 3) && tg != nil
    hx = if (face) { dx / d } else { elem(wh, 0) }
    hy = if (face) { dy / d } else { elem(wh, 1) }
    speed = if (mode2 == 1) { 0.0080 } else { if (mode2 == 0) { 0.0032 } else { 0.0 } }
    nx = clampw(px + hx * speed)
    ny = clampw(py + hy * speed)
    if (mode2 == 1 && tg != nil && d < 0.05) {
        s1 = p(s, 'crs', bite_creature(g(s, 'crs'), hd(tl(tg)), dx / d * 0.09, dy / d * 0.09))
        {s1, [nx, ny, 2, 150, hx, hy]}
    } else { {s, [nx, ny, mode2, tm2, hx, hy]} }
}

fun preds_step(s, lst, acc) {
    if (length(lst) == 0) { p(s, 'preds', acc) }
    else {
        r = pred_one(s, hd(lst))
        preds_step(elem(r, 0), tl(lst), [elem(r, 1) | acc])
    }
}

fun pred_step(s) { if (g(s, 'pred_on') != 1) { s } else { preds_step(s, g(s, 'preds'), []) } }

# ---- creature vs creature: aggressive strangers bite, armour reduces the damage, a bite feeds the attacker ----
fun find_c(crs, id) {
    if (length(crs) == 0) { nil } else { if (g(hd(crs), 'id') == id) { hd(crs) } else { find_c(tl(crs), id) } }
}

fun nearest_prey(crs, a, best) {
    if (length(crs) == 0) { if (best == nil) { nil } else { elem(best, 1) } }
    else {
        c = hd(crs)
        dx = g(c, 'x') - g(a, 'x')
        dy = g(c, 'y') - g(a, 'y')
        d = Math.sqrt(dx * dx + dy * dy)
        reach = 0.045 + 0.02 * g(a, 'size')
        ok = g(c, 'id') != g(a, 'id') && g(c, 'h') > 0.0 && hue_gap(g(a, 'hue'), g(c, 'hue')) >= 25 && d < reach
        nearest_prey(tl(crs), a, if (ok && (best == nil || d < elem(best, 0))) { {d, g(c, 'id')} } else { best })
    }
}

fun hit_creature(crs, id, dmg, aid) {
    if (length(crs) == 0) { [] }
    else {
        c = hd(crs)
        if (g(c, 'id') == id) {
            [add_ev(p(p(p(p(c, 'h', g(c, 'h') - dmg), 'pain', 14), 'bitten', g(c, 'bitten') + 1), 'by', aid), 3) | tl(crs)]
        } else { [c | hit_creature(tl(crs), id, dmg, aid)] }
    }
}

fun feed_creature(crs, id, gain, dead) {
    if (length(crs) == 0) { [] }
    else {
        c = hd(crs)
        if (g(c, 'id') == id) {
            [p(p(p(c, 'e', fmin(100.0, g(c, 'e') + gain)), 'acd', 16), 'kills', g(c, 'kills') + (if (dead) { 1 } else { 0 })) | tl(crs)]
        } else { [c | feed_creature(tl(crs), id, gain, dead)] }
    }
}

fun combat(crs, snap) {
    if (length(snap) == 0) { crs }
    else {
        a = find_c(crs, g(hd(snap), 'id'))
        if (a != nil && g(a, 'aggr') >= 0.5 && g(a, 'acd') <= 0 && g(a, 'h') > 0.0) {
            tid = nearest_prey(crs, a, nil)
            if (tid == nil) { combat(crs, tl(snap)) }
            else {
                tc = find_c(crs, tid)
                dmg = 8.0 * g(a, 'atk') * g(a, 'size') / (1.0 + 0.9 * g(tc, 'arm'))
                dead = g(tc, 'h') - dmg <= 0.0
                crs2 = hit_creature(crs, tid, dmg, g(a, 'id'))
                crs3 = feed_creature(crs2, g(a, 'id'), dmg * 0.45 + (if (dead) { 15.0 } else { 0.0 }), dead)
                combat(crs3, tl(snap))
            }
        } else { combat(crs, tl(snap)) }
    }
}

# slim list other creatures see: [x, y, hue, aggr*100, id]
fun others_list(crs) {
    if (length(crs) == 0) { [] }
    else {
        c = hd(crs)
        [[g(c, 'x'), g(c, 'y'), g(c, 'hue'), Math.round(g(c, 'aggr') * 100.0), g(c, 'id')] | others_list(tl(crs))]
    }
}

fun excl(lst, id) {
    if (length(lst) == 0) { [] }
    else { if (hd(tl(tl(tl(tl(hd(lst)))))) == id) { excl(tl(lst), id) } else { [hd(lst) | excl(tl(lst), id)] } }
}

# ---- metabolism: every gene costs energy ----
fun vitals_c(c) {
    cost = 0.026 + 0.00005 * to_float(g(c, 'm')) + 0.03 * g(c, 'vis') + 0.012 * g(c, 'speed') * g(c, 'speed') + 0.008 * g(c, 'atk') * g(c, 'atk') + 0.009 * g(c, 'arm') * g(c, 'arm') + 0.012 * g(c, 'size') * g(c, 'size') + 0.014 * g(c, 'aggr')
    regen = if (g(c, 'e') > 50.0 && g(c, 'h') < 100.0) { 0.03 } else { 0.0 }
    p(p(p(p(p(c, 'e', g(c, 'e') - cost), 'h', fmin(100.0, g(c, 'h') + regen)), 'age', g(c, 'age') + 1),
        'pain', if (g(c, 'pain') > 0) { g(c, 'pain') - 1 } else { 0 }), 'cool', g(c, 'cool') - 1) |> tick_acd() |> clear_ev()
}

fun tick_acd(c) { if (g(c, 'acd') > 0) { p(c, 'acd', g(c, 'acd') - 1) } else { c } }

fun clear_ev(c) { p(c, 'ev', []) }

# ------------------------------------------------------------
# The tick: sense -> brains -> act -> items -> predator -> metabolism -> life cycle
# ------------------------------------------------------------
fun view(s, c) { p(p(p(p(p(c, 'food', g(s, 'food')), 'poison', g(s, 'poison')), 'preds', g(s, 'preds')), 'pred_on', g(s, 'pred_on')), 'oth', excl(g(s, 'orth'), g(c, 'id'))) }

# one entry per creature: {creature, rays, expert command}
fun perceive(s, tab, crs, acc) {
    if (length(crs) == 0) { acc }
    else {
        c = hd(crs)
        v = view(s, c)
        rays = all_rays(v, 0)
        ex = expert(v)
        inject_all(tab, g(c, 'slot'), g(c, 'm'), sensor_ids(v, rays))
        perceive(s, tab, tl(crs), [{c, rays, ex} | acc])
    }
}

fun tick_neurons(tab, slot, i, m) {
    if (i >= m) { 'ok' }
    else {
        t = tget(tab, slot * maxm + i)
        if (t == nil) { 'skip' } else { send(t, {'tick'}) }
        tick_neurons(tab, slot, i + 1, m)
    }
}

fun tick_motors(tab, slot, mi, cmd) {
    if (mi >= 4) { 'ok' }
    else {
        t = tget(tab, k_motor + slot * 4 + mi)
        if (t == nil) { 'skip' } else { send(t, {'tick', elem(cmd, mi)}) }
        tick_motors(tab, slot, mi + 1, cmd)
    }
}

fun tick_brains(tab, perc) {
    if (length(perc) == 0) { 'ok' }
    else {
        e = hd(perc)
        c = elem(e, 0)
        tick_neurons(tab, g(c, 'slot'), 0, g(c, 'm'))
        tick_motors(tab, g(c, 'slot'), 0, elem(e, 2))
        tick_brains(tab, tl(perc))
    }
}

fun drain(fired, flags) {
    receive {
        {'f', gid} -> drain([gid | fired], flags)
        {'m', slot, mi} -> drain(fired, set_flag(flags, slot * 4 + mi))
        after 0 { {fired, flags} }
    }
}

fun set_flag(lst, k) {
    if (length(lst) == 0) { [] }
    else { if (k <= 0) { [1 | tl(lst)] } else { [hd(lst) | set_flag(tl(lst), k - 1)] } }
}

fun zeros(k) { if (k <= 0) { [] } else { [0 | zeros(k - 1)] } }
fun nth(lst, k) { if (k <= 0) { hd(lst) } else { nth(tl(lst), k - 1) } }

# every creature decides and moves; they share the food and poison
fun act_all(perc, flags, food, poison, pred_on, out, rays_out) {
    if (length(perc) == 0) { {food, poison, out, rays_out} }
    else {
        e = hd(perc)
        c = elem(e, 0)
        ex = elem(e, 2)
        slot = g(c, 'slot')
        bc = {nth(flags, slot * 4), nth(flags, slot * 4 + 1), nth(flags, slot * 4 + 2), nth(flags, slot * 4 + 3)}
        ok = (if (elem(bc, 0) == elem(ex, 0)) { 1 } else { 0 }) + (if (elem(bc, 1) == elem(ex, 1)) { 1 } else { 0 }) +
             (if (elem(bc, 2) == elem(ex, 2)) { 1 } else { 0 }) + (if (elem(bc, 3) == elem(ex, 3)) { 1 } else { 0 })
        acc = g(c, 'acc') * 0.99 + (to_float(ok) / 4.0) * 0.01
        share = fmax(0.0, fmin(0.85, (0.88 - acc) / 0.4))
        cmd = if (rndf() < share) { ex } else { bc }
        it = items_step(move(c, cmd), food, poison)
        c2 = p(p(p(elem(it, 0), 'acc', acc), 'share', share), 'bcmd', [elem(bc, 0), elem(bc, 1), elem(bc, 2), elem(bc, 3)])
        act_all(tl(perc), flags, elem(it, 1), elem(it, 2), pred_on, [p(c2, 'ex', [elem(ex, 0), elem(ex, 1), elem(ex, 2), elem(ex, 3)]) | out], [{g(c, 'id'), elem(e, 1)} | rays_out])
    }
}

# ---- life cycle ----
fun used_slot(crs, slot) {
    if (length(crs) == 0) { 'false' }
    else { if (g(hd(crs), 'slot') == slot) { 'true' } else { used_slot(tl(crs), slot) } }
}

fun pick_slot(crs, k) {
    if (k >= max_slots) { -1 } else { if (used_slot(crs, k) == 'false') { k } else { pick_slot(crs, k + 1) } }
}

fun hue_mix(h) { (h + 360 + (rndi(25) - 12)) % 360 }

# a creature is added with its own freshly spawned brain
fun add_creature(tab, world, s, gn, par, hue) {
    crs = g(s, 'crs')
    slot = pick_slot(crs, 0)
    if (slot < 0) { s }
    else {
        m = g(gn, 'm')
        spawn_brain(tab, slot, m, world, 0)
        wait_brain(tab, slot, 0, m, timestamp() + 2500)
        inherit = if (par != nil && g(par, 'm') == m) { copy_w(tab, g(par, 'slot'), slot, 0, m) } else { 'fresh' }
        pos = if (par != nil) { [clampw(g(par, 'x') + (rndf() - 0.5) * 0.08), clampw(g(par, 'y') + (rndf() - 0.5) * 0.08)] } else { free_pos(30) }
        id = g(s, 'next_id')
        c = new_creature(id, slot, if (par == nil) { 0 } else { g(par, 'gen') + 1 }, if (par == nil) { 0 } else { g(par, 'id') }, hue, gn, hd(pos), hd(tl(pos)), if (par == nil) { 70.0 } else { 40.0 })
        c2 = if (par != nil && g(par, 'm') == m) { p(p(c, 'acc', g(par, 'acc')), 'share', g(par, 'share')) } else { c }
        s1 = p(p(s, 'crs', app(crs, [c2])), 'next_id', id + 1)
        s2 = if (par != nil) { p(p(s1, 'births', g(s1, 'births') + 1), 'maxgen', if (g(c2, 'gen') > g(s1, 'maxgen')) { g(c2, 'gen') } else { g(s1, 'maxgen') }) } else { s1 }
        p(s2, 'evs', [[7, slot, hue, g(c2, 'gen'), m, Math.round(g(c2, 'atk') * 100.0), Math.round(g(c2, 'arm') * 100.0)] | g(s2, 'evs')])
    }
}

# deaths: free the brain (its processes stop), record why
fun reap(tab, s, crs, keep) {
    if (length(crs) == 0) { p(s, 'crs', keep) }
    else {
        c = hd(crs)
        if (g(c, 'e') <= 0.0 || g(c, 'h') <= 0.0) {
            slain = g(c, 'h') <= 0.0
            devoured = slain && g(c, 'by') > 0
            kill_brain(tab, g(c, 'slot'), 0, g(c, 'm'))
            key = if (devoured) { 'devoured' } else { if (slain) { 'slain' } else { 'starved' } }
            s1 = p(p(s, 'deaths', g(s, 'deaths') + 1), key, g(s, key) + 1)
            s2 = p(s1, 'record', if (g(c, 'age') > g(s1, 'record')) { g(c, 'age') } else { g(s1, 'record') })
            reap(tab, p(s2, 'evs', [[if (devoured) { 6 } else { if (slain) { 5 } else { 4 } }, g(c, 'slot'), g(c, 'hue'), g(c, 'gen'), g(c, 'age'), g(c, 'eaten')] | g(s2, 'evs')]), tl(crs), keep)
        } else { reap(tab, s, tl(crs), [c | keep]) }
    }
}

# births: any creature with surplus energy and no cool-down has a child
fun breed(tab, world, s, crs, done) {
    if (length(crs) == 0) { s }
    else {
        c = hd(crs)
        if (g(c, 'e') >= 80.0 && g(c, 'age') >= 220 && g(c, 'cool') <= 0 && length(g(s, 'crs')) < max_slots) {
            gn = mutate(genome_of(c))
            s1 = add_creature(tab, world, s, gn, c, hue_mix(g(c, 'hue')))
            s2 = if (length(g(s1, 'crs')) > length(g(s, 'crs'))) { update_creature(s1, g(c, 'id'), 'paid') } else { s1 }
            breed(tab, world, s2, tl(crs), done)
        } else { breed(tab, world, s, tl(crs), done) }
    }
}

# the parent pays: energy and a cool-down
fun update_creature(s, id, why) { p(s, 'crs', pay(g(s, 'crs'), id)) }
fun pay(crs, id) {
    if (length(crs) == 0) { [] }
    else {
        c = hd(crs)
        if (g(c, 'id') == id) { [p(p(c, 'e', g(c, 'e') - 35.0), 'cool', 220) | tl(crs)] } else { [c | pay(tl(crs), id)] }
    }
}

fun founders(tab, world, s, k) {
    if (k <= 0) { s } else { founders(tab, world, add_creature(tab, world, s, random_genome(), nil, rndi(360)), k - 1) }
}

# ------------------------------------------------------------
# The world loop
# ------------------------------------------------------------
fun world_loop(tab, s) {
    if (g(s, 'init') == 0) {
        s1 = founders(tab, self(), s, 12)
        world_loop(tab, p(s1, 'init', 1))
    } else {
        if (num(cget(tab, 'reset')) == 1) {
            cput(tab, 'reset', 0)
            s0 = kill_all(tab, g(s, 'crs'), new_world())
            world_loop(tab, p(s0, 'init', 0))
        } else {
            t0 = timestamp()
            sp = if (num(cget(tab, 'speed')) < 1) { 1 } else { num(cget(tab, 'speed')) }
            s0 = p(p(s, 'pred_on', num(cget(tab, 'pred_on'))), 'orth', others_list(g(s, 'crs')))
            perc = perceive(s0, tab, g(s0, 'crs'), [])
            tick_brains(tab, perc)
            sleep(if (sp == 1) { 11 } else { if (sp == 2) { 6 } else { 4 } })
            got = drain([], zeros(max_slots * 4))
            fired = elem(got, 0)
            flags = elem(got, 1)
            act = act_all(perc, flags, g(s0, 'food'), g(s0, 'poison'), g(s0, 'pred_on'), [], [])
            crs0 = combat(elem(act, 2), elem(act, 2))
            crs1 = map_vitals(crs0, [])
            s1 = pred_step(p(p(p(s0, 'food', elem(act, 0)), 'poison', elem(act, 1)), 'crs', crs1))
            s2 = reap(tab, s1, g(s1, 'crs'), [])
            s3 = breed(tab, self(), s2, g(s2, 'crs'), 0)
            tick = num(cget(tab, 'tick'))
            cput(tab, 'tick', tick + 1)
            s4 = if (length(g(s3, 'crs')) < 5 && tick % 90 == 0) { add_creature(tab, self(), s3, random_genome(), nil, rndi(360)) } else { s3 }
            cput(tab, 'win_spikes', num(cget(tab, 'win_spikes')) + length(fired))
            if (tick % 40 == 0) { cput(tab, 'sps', num(cget(tab, 'win_spikes')))  cput(tab, 'win_spikes', 0) } else { 'x' }
            sel = selected(tab, g(s4, 'crs'))
            if (tick % 40 == 0 && sel >= 0) { cput(tab, 'topw', top_weights(tab, sel, sel_m(g(s4, 'crs'), sel))) } else { 'x' }
            emit = tick % sp == 0
            if (emit) { frame(tab, s4, tick, fired, flags, elem(act, 3), sel) } else { 'skip' }
            spent = timestamp() - t0
            period = tick_ms / sp
            if (spent < period) { sleep(period - spent) } else { 'late' }
            world_loop(tab, p(p(s4, 'tick', tick), 'evs', if (emit) { [] } else { g(s4, 'evs') }))
        }
    }
}

fun map_vitals(crs, acc) {
    if (length(crs) == 0) { acc } else { map_vitals(tl(crs), [vitals_c(hd(crs)) | acc]) }
}

fun kill_all(tab, crs, s) {
    if (length(crs) == 0) { s }
    else { kill_brain(tab, g(hd(crs), 'slot'), 0, g(hd(crs), 'm'))  kill_all(tab, tl(crs), s) }
}

# which creature's brain the page is showing: the chosen slot if alive, else the oldest
fun selected(tab, crs) {
    want = num(cget(tab, 'sel'))
    if (length(crs) == 0) { -1 }
    else { if (used_slot(crs, want) == 'true') { want } else { oldest_slot(crs, hd(crs)) } }
}

fun oldest_slot(crs, best) {
    if (length(crs) == 0) { g(best, 'slot') }
    else { oldest_slot(tl(crs), if (g(hd(crs), 'age') > g(best, 'age')) { hd(crs) } else { best }) }
}

fun sel_m(crs, slot) {
    if (length(crs) == 0) { 0 } else { if (g(hd(crs), 'slot') == slot) { g(hd(crs), 'm') } else { sel_m(tl(crs), slot) } }
}

# ---- frames ----
fun r3(v) { Math.round(v * 1000) }

fun cr_row(c) {
    [g(c, 'slot'), g(c, 'id'), g(c, 'gen'), g(c, 'hue'), r3(g(c, 'x')), r3(g(c, 'y')), r3(g(c, 'hx')), r3(g(c, 'hy')),
     Math.round(g(c, 'e')), Math.round(g(c, 'h')), Math.round(g(c, 'speed') * 100.0), Math.round(g(c, 'vis') * 100.0),
     g(c, 'm'), g(c, 'age'), g(c, 'eaten'), r3(g(c, 'share')), r3(g(c, 'acc')),
     Math.round(g(c, 'caution') * 100.0), Math.round(g(c, 'hunger')), g(c, 'poisoned'), g(c, 'bitten'),
     Math.round(g(c, 'atk') * 100.0), Math.round(g(c, 'arm') * 100.0), Math.round(g(c, 'size') * 100.0), Math.round(g(c, 'aggr') * 100.0),
     Math.round(g(c, 'mut') * 100.0), g(c, 'kills'), g(c, 'pain')]
}

fun cr_rows(crs) { if (length(crs) == 0) { [] } else { [cr_row(hd(crs)) | cr_rows(tl(crs))] } }

fun pts(lst, present_only) {
    if (length(lst) == 0) { [] }
    else {
        it = hd(lst)
        if (present_only == 1 && hd(tl(tl(it))) > 0) { pts(tl(lst), present_only) }
        else { [[r3(hd(it)), r3(hd(tl(it)))] | pts(tl(lst), present_only)] }
    }
}

fun pred_pts(lst) {
    if (length(lst) == 0) { [] }
    else { [[r3(hd(hd(lst))), r3(hd(tl(hd(lst)))), hd(tl(tl(hd(lst)))), hd(tl(tl(tl(hd(lst)))))] | pred_pts(tl(lst))] }
}

fun obst_pts(lst) {
    if (length(lst) == 0) { [] }
    else { [[r3(hd(hd(lst))), r3(hd(tl(hd(lst)))), r3(hd(tl(tl(hd(lst)))))] | obst_pts(tl(lst))] }
}

fun ray_pts(lst) {
    if (length(lst) == 0) { [] }
    else { [[r3(hd(hd(lst))), hd(tl(hd(lst)))] | ray_pts(tl(lst))] }
}

fun rays_of(rays_out, id) {
    if (length(rays_out) == 0) { [] }
    else { if (elem(hd(rays_out), 0) == id) { ray_pts(elem(hd(rays_out), 1)) } else { rays_of(tl(rays_out), id) } }
}

# the selected creature's neurons that spiked (local ids) — others stay quiet to keep frames small
fun local_spikes(fired, slot, acc) {
    if (length(fired) == 0) { acc }
    else {
        gid = hd(fired)
        local_spikes(tl(fired), slot, if (gid / maxm == slot) { [gid % maxm | acc] } else { acc })
    }
}

fun sum_key(crs, k, acc) { if (length(crs) == 0) { acc } else { sum_key(tl(crs), k, acc + g(hd(crs), k)) } }

fun mean_key(crs, k) { if (length(crs) == 0) { 0.0 } else { sum_key(crs, k, 0.0) / to_float(length(crs)) } }
fun mean_m(crs) { if (length(crs) == 0) { 0.0 } else { to_float(sum_int(crs, 0)) / to_float(length(crs)) } }
fun sum_int(crs, acc) { if (length(crs) == 0) { acc } else { sum_int(tl(crs), acc + g(hd(crs), 'm')) } }

fun creature_by_slot(crs, slot) {
    if (length(crs) == 0) { nil } else { if (g(hd(crs), 'slot') == slot) { hd(crs) } else { creature_by_slot(tl(crs), slot) } }
}

fun frame(tab, s, tick, fired, flags, rays_out, sel) {
    st = swarm_stats()
    crs = g(s, 'crs')
    sps = num(cget(tab, 'sps'))
    sc = if (sel >= 0) { creature_by_slot(crs, sel) } else { nil }
    LiveView.broadcast("evolve2", {'frame', json_encode(%{t: "ev", n: "frame", d: %{
        tick: tick, cr: cr_rows(crs), sel: sel,
        s: if (sel >= 0) { local_spikes(fired, sel, []) } else { [] },
        mo: if (sel >= 0) { [nth(flags, sel * 4), nth(flags, sel * 4 + 1), nth(flags, sel * 4 + 2), nth(flags, sel * 4 + 3)] } else { [0, 0, 0, 0] },
        ex: if (sc != nil && g(sc, 'ex') != nil) { g(sc, 'ex') } else { [0, 0, 0, 0] },
        rays: if (sc != nil) { rays_of(rays_out, g(sc, 'id')) } else { [] },
        tw: if (tick % 40 == 0) { list_or_empty(cget(tab, 'topw')) } else { [] },
        food: pts(g(s, 'food'), 1), poison: pts(g(s, 'poison'), 0),
        preds: pred_pts(g(s, 'preds')),
        obst: obst_pts(obstacles()),
        pop: length(crs), births: g(s, 'births'), deaths: g(s, 'deaths'), starved: g(s, 'starved'), slain: g(s, 'slain'), devoured: g(s, 'devoured'),
        maxgen: g(s, 'maxgen'), record: g(s, 'record'),
        mean: [Math.round(mean_key(crs, 'speed') * 100.0), Math.round(mean_key(crs, 'vis') * 100.0), Math.round(mean_m(crs)),
               Math.round(mean_key(crs, 'caution') * 100.0), Math.round(mean_key(crs, 'hunger')),
               Math.round(mean_key(crs, 'atk') * 100.0), Math.round(mean_key(crs, 'arm') * 100.0), Math.round(mean_key(crs, 'size') * 100.0),
               Math.round(mean_key(crs, 'aggr') * 100.0), Math.round(mean_key(crs, 'mut') * 100.0)],
        procs: num(map_get(st, 'processes')), sps: sps, learn: num(cget(tab, 'learn')), pred_on: g(s, 'pred_on'), speed: num(cget(tab, 'speed')),
        evs: g(s, 'evs')
    }})})
}

fun top_weights(tab, slot, m) {
    app(top_for(tab, slot, 0, 0, m, []), app(top_for(tab, slot, 1, 0, m, []), app(top_for(tab, slot, 2, 0, m, []), top_for(tab, slot, 3, 0, m, []))))
}

fun top_for(tab, slot, mi, i, m, acc) {
    if (i >= m) { acc }
    else {
        w = numf(tget(tab, wkey(slot, mi, i)))
        if (w > 0.12) { top_for(tab, slot, mi, i + 1, m, top_insert(acc, [mi, i, Math.round(w * 100.0)], 10)) }
        else { top_for(tab, slot, mi, i + 1, m, acc) }
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
        {'learn'} ->
            cput(tab, 'learn', 1 - num(cget(tab, 'learn')))
            inbox(tab)
        {'pred'} ->
            cput(tab, 'pred_on', 1 - num(cget(tab, 'pred_on')))
            inbox(tab)
        {'sel', slot} ->
            cput(tab, 'sel', slot)
            inbox(tab)
        {'speed', k} ->
            cput(tab, 'speed', k)
            inbox(tab)
        {'reset'} ->
            cput(tab, 'reset', 1)
            inbox(tab)
        _o -> inbox(tab)
    }
}

fun inbox_send(msg) {
    a = whereis('evolve2_in')
    if (a == nil) { 'noop' } else { send(a, msg) }
}

# ------------------------------------------------------------
# View — static shell; motion is in evolve.js
# ------------------------------------------------------------
fun mount(params) {
    if (LiveView.connected(params) == 'true') { LiveView.subscribe("evolve2") } else { 'noop' }
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
    ".body{flex:1;min-height:0;display:grid;grid-template-columns:minmax(0,1.55fr) minmax(0,.7fr) 330px;gap:14px}" ++
    ".pane{position:relative;overflow:hidden;background:#040406;min-height:0}.pane canvas{position:absolute;inset:0}" ++
    ".ph{position:absolute;top:12px;left:14px;font-size:12px;color:var(--mu);pointer-events:none}.ph b{color:var(--tx)}" ++
    ".col{display:flex;flex-direction:column;gap:12px;min-height:0;overflow:auto}" ++
    ".col .card{padding:12px 14px;flex:none}.col h3{font-size:12px;font-weight:600;margin:0 0 9px;display:flex;justify-content:space-between}.col h3 span{color:var(--mu);font-weight:400}" ++
    ".chart{width:100%;height:78px;display:block}" ++
    "#log{font:11.5px/1.5 ui-sans-serif,-apple-system,sans-serif;height:128px;overflow:hidden}" ++
    ".ev{display:flex;gap:8px;padding:2px 0;animation:in .3s ease}.ev i{width:7px;height:7px;border-radius:50%;margin-top:5px;flex:none}.ev time{margin-left:auto;color:#666;font-size:10px}" ++
    "@keyframes in{from{opacity:0;transform:translateY(-5px)}to{opacity:1;transform:none}}" ++
    ".row2{display:flex;gap:7px;margin-bottom:7px}.btn{flex:1;font:inherit;font-size:11.5px;font-weight:500;color:var(--tx);background:#111;border:1px solid var(--line2);border-radius:8px;padding:7px 8px;cursor:pointer}" ++
    ".btn:hover{background:#1a1a1a;border-color:#444}.btn.on{background:#e6e6e6;color:#06070a;border-color:#e6e6e6}" ++
    ".btn.danger{color:#ff9a9a;border-color:#5b2020;background:#1a0b0b}.btn.danger:hover{background:#2a1010;border-color:var(--red)}" ++
    ".how{font-size:11.5px;color:var(--mu);line-height:1.55;margin:0}.how b{color:var(--tx);font-weight:600}" ++
    ".lb{font:11px ui-sans-serif,-apple-system,sans-serif}.lr{display:grid;grid-template-columns:14px 1fr auto;gap:8px;align-items:center;padding:3px 0;cursor:pointer}.lr:hover{background:#111}.lr i{width:10px;height:10px;border-radius:50%}.lr b{font-weight:500;color:var(--mu)}" ++
    "@media(max-width:1180px){.cards{grid-template-columns:repeat(3,1fr)}.body{grid-template-columns:1fr}body{overflow:auto}#live-root{height:auto}.pane{height:520px}}" ++
    "</style>"
}

fun render(assigns) {
    LiveView.h(
        css() ++
        "<header class=\"nav\"><div class=\"logo\">" ++
        "<svg width=\"22\" height=\"22\" viewBox=\"0 0 22 22\"><circle cx=\"6\" cy=\"6\" r=\"2.4\" fill=\"#ededed\"/><circle cx=\"16\" cy=\"6\" r=\"2.4\" fill=\"#888\"/><circle cx=\"11\" cy=\"16\" r=\"2.4\" fill=\"#555\"/><path d=\"M6 6L16 6M6 6L11 16M16 6L11 16\" stroke=\"#444\"/></svg>" ++
        "Evolution 2</div><span class=\"crumb\">microbes with attack, armor and their own brains of processes</span>" ++
        "<div class=\"live\"><span class=\"dot\"></span>live &middot; <span id=\"o-fps\">0</span> fps</div></header>" ++
        "<div class=\"main\"><div class=\"cards\">" ++
        stat("pop", "Population") ++ stat("gen", "Newest generation") ++ stat("procs", "Neuron processes alive") ++
        stat("rec", "Longest life") ++ stat("birth", "Births") ++ stat("death", "Deaths") ++
        "</div><div class=\"body\">" ++
        "<div class=\"card pane\" id=\"arena\"><canvas id=\"arena-cv\" sw-keep></canvas><div class=\"ph\" id=\"ah\" sw-keep>the world</div></div>" ++
        "<div class=\"card pane\" id=\"brain\"><canvas id=\"brain-cv\" sw-keep></canvas><div class=\"ph\" id=\"bh\" sw-keep>click a creature to see its brain</div></div>" ++
        "<div class=\"col\">" ++
        "<div class=\"card\"><h3>Traits over time <span>population mean</span></h3><canvas id=\"chart-cv\" class=\"chart\" sw-keep></canvas><p class=\"how\" id=\"h-traits\" style=\"margin-top:6px\">waiting for data</p></div>" ++
        "<div class=\"card\"><h3>Gene pool <span>attack vs armor, one dot per creature</span></h3><canvas id=\"gene-cv\" class=\"chart\" style=\"height:130px\" sw-keep></canvas></div>" ++
        "<div class=\"card\"><h3>Population <span id=\"h-pop\"></span></h3><canvas id=\"pop-cv\" class=\"chart\" sw-keep></canvas></div>" ++
        "<div class=\"card\"><h3>Longest-lived now <span>click to inspect</span></h3><div class=\"lb\" id=\"lb\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Life and death</h3><div id=\"log\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Experiments</h3><div class=\"row2\"><button class=\"btn on\" id=\"b-learn\">Plasticity: on</button><button class=\"btn on\" id=\"b-pred\">Predators: on</button></div>" ++
        "<h3>Time-lapse</h3><div class=\"row2\"><button class=\"btn\" data-speed=\"1\">1x</button><button class=\"btn\" data-speed=\"2\">2x</button><button class=\"btn\" data-speed=\"4\">max</button></div><div class=\"row2\" style=\"margin-bottom:0\"><button class=\"btn danger\" id=\"b-reset\">Extinction event</button></div></div>" ++
        "<div class=\"card\"><h3>Reading a microbe</h3><p class=\"how\"><b>Spikes</b> = attack (red-hot: it hunts other creatures). <b>Shell plates</b> = armor. <b>Tail</b> = speed. <b>Eye</b> = sight range. <b>Nucleus</b> = brain size. <b>Body</b> = size. The ring is energy, the red ring health. Strangers of a different colour can eat each other; kin never fight.</p></div>" ++
        "<div class=\"card\"><h3>How it works</h3><p class=\"how\">Every creature owns a swarm of <b>neuron processes</b>. With spare energy it has a child whose <b>ten genes</b> mutate (each creature even carries its own mutation rate, plus rare big jumps). Every trait burns energy, so there are trade-offs: armor slows you, spikes cost food, big brains cost more. <b>Predators stalk first</b> (a warning ring), then chase for a short time, then rest, so you can run. Nobody picks the winners. Honest label: this evolves bodies and temperaments; learning inside a life is imitation of a built-in expert, not open-ended evolution.</p></div>" ++
        "</div></div></div>",
        [])
}

fun handle_event(name, value, assigns) {
    if (name == "learn") {
        inbox_send({'learn'})
    } else { if (name == "pred") {
        inbox_send({'pred'})
    } else { if (name == "reset") {
        inbox_send({'reset'})
    } else { if (name == "sel") {
        inbox_send({'sel', to_int(map_get(value, 'slot'))})
    } else { if (name == "speed") {
        inbox_send({'speed', to_int(map_get(value, 'k'))})
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
    cput(tab, 'pred_on', 1)
    cput(tab, 'speed', 1)
    start_sups(tab, 0)
    world = spawn(world_loop(tab, new_world()))
    register('evolve2_world', world)
    register('evolve2_in', spawn(inbox(tab)))
    start_motors(tab, world, 0, 0)
    LiveView.start(4015, [
        {"/", %{
            title: "Evolution 2",
            js: Evolve2Js.js(),
            mount: mount,
            render: render,
            handle_event: handle_event,
            handle_info: handle_info
        }}
    ])
}

fun start_sups(tab, k) {
    if (k >= max_slots) { 'ok' }
    else {
        cput(tab, k_sup + k, dyn_supervisor(1000000, 1))
        start_sups(tab, k + 1)
    }
}

fun start_motors(tab, world, slot, mi) {
    if (slot >= max_slots) { 'ok' }
    else { if (mi >= 4) { start_motors(tab, world, slot + 1, 0) }
    else { spawn(motor(slot, mi, tab, world))  start_motors(tab, world, slot, mi + 1) } }
}
