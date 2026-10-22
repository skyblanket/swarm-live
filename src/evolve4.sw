module Main

# swarm-live — Evolution 3: real neuroevolution
#
#   make bin/evolve3 && scripts/run.sh evolve3      ->  http://localhost:4016
#
# No expert, no teacher. Every creature's brain is written in its genome and every
# neuron is a swarmrt process. Nothing tells a creature what to do: brains that
# happen to find food, flee and mate leave children; the rest starve.
#
#   GENOME     diploid: two copies (haplotypes) of every gene. Body loci carry an
#              allele value and a dominance; the expressed trait is the
#              dominance-weighted blend, so recessive variation hides and returns.
#              Brain genes are neurons and synapses (NEAT-style ids from a hash of
#              the split connection, so the same innovation lines up across lineages).
#   SEX        two willing, fertile, compatible creatures that meet have a child:
#              each parent makes a gamete by meiosis (crossover between its two
#              haplotypes with linkage) plus mutation. A creature with plenty of
#              energy and no partner can bud (self-fertilise), which costs more.
#   BRAIN      a hybrid net: rate neurons (leaky tanh), spiking neurons (integrate
#              and fire) and modulatory neurons. Synapses learn during a life by an
#              evolved rule  dw = eta * tanh(m0 + modulation) * (A*pre*post + B*pre + C*post + D)
#              — eta, A..D and m0 are genes. Learned weights are NOT inherited.
#   COST       every neuron and every synapse (one message per tick) costs energy.
#   SPECIES    creatures are grouped by genetic distance to a type specimen;
#              mates must be genetically close (the creature's choosiness gene).
#   CHECKPOINT the population's genomes are saved to checkpoints/evolve3/ and
#              reloaded at start, so evolution keeps going across runs.

import LiveView
import Evolve4Js
import Math
import Std

let max_slots = 400
let isl_cap = 400
let WS = 1.6
let k_lin = 500000000
let k_dead = 2000000000
let k_isl = 300000
let nmax = 64
let n_out = 5
let n_sens = 23
let n_loci = 19
let cmax = 160
let tick_ms = 25
let k_act = 10000000
let k_w = 20000000
let ck_dir = "checkpoints/evolve4"

#           size speed armor attack sight diet  hue    p1   p2   p3   mut  eta  A     B     C     D     m0    fert choosy
let LO = [0.6, 0.5, 0.0, 0.0, 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.0, -1.0, -1.0, -1.0, -0.3, -2.0, 45.0, 0.4]
let HI = [1.6, 1.8, 1.5, 2.0, 0.5, 1.0, 360.0, 1.0, 1.0, 1.0, 3.0, 0.2, 1.0, 1.0, 1.0, 0.3, 2.0, 95.0, 2.5]
# LO/HI are only the typical range (for starting values, mutation step size and display). Genes are NOT clamped to it:
# they can evolve as far as energy costs allow. Only physical floors and the few true fractions are bounded.
let FLOOR = [0.2, 0.05, 0.0, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.0, -50.0, -50.0, -50.0, -50.0, -50.0, 20.0, 0.0]
let CEIL = [1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1.0, 360.0, 1.0, 1.0, 1.0, 1000.0, 1000.0, 50.0, 50.0, 50.0, 50.0, 50.0, 100.0, 1000.0]

fun num(x) { if (x == nil) { 0 } else { x } }
fun list_or_empty(x) { if (x == nil) { [] } else { x } }
fun tget(tab, k) { ets_get(tab + k % 16, k) }
fun tput(tab, k, v) { ets_put(tab + k % 16, k, v) }
fun cget(tab, k) { ets_get(tab + 16, k) }
fun cput(tab, k, v) { ets_put(tab + 16, k, v) }
fun fmin(a, b) { if (a < b) { a } else { b } }
fun fmax(a, b) { if (a > b) { a } else { b } }
fun fabs(a) { if (a < 0.0) { 0.0 - a } else { a } }
fun clampf(v, lo, hi) { if (v < lo) { lo } else { if (v > hi) { hi } else { v } } }
fun g(s, k) { map_get(s, k) }
fun p(s, k, v) { map_put(s, k, v) }
fun app(a, b) { app_rev(rev(a, []), b) }
fun app_rev(ra, b) { if (length(ra) == 0) { b } else { app_rev(tl(ra), [hd(ra) | b]) } }
fun nth(lst, k) { if (k <= 0) { hd(lst) } else { nth(tl(lst), k - 1) } }
fun rev(l, acc) { if (length(l) == 0) { acc } else { rev(tl(l), [hd(l) | acc]) } }
fun lo(k) { nth(LO, k) }
fun is_sens(s) { s >= 1000 && s < 2000 }
fun hi(k) { nth(HI, k) }

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

fun rndf() { to_float(random_int(0, 999999)) / 1000000.0 }
fun rndi(n) { if (n <= 1) { 0 } else { random_int(0, n - 1) } }
fun gauss() { (rndf() + rndf() + rndf() - 1.5) * 1.15 }

fun tanh(x) {
    if (x > 9.0) { 1.0 }
    else { if (x < 0.0 - 9.0) { 0.0 - 1.0 } else { e2 = Math.exp(2.0 * x)  (e2 - 1.0) / (e2 + 1.0) } }
}

fun hue_gap(a, b) {
    d = fabs(a - b)
    if (d > 180.0) { 360.0 - d } else { d }
}

# ------------------------------------------------------------
# Genome: a haplotype is %{b: [[value, dominance] x 19], n: [[id, type, bias, tau]], c: [[src, dst, w]]}
#   neuron ids 0..4 are the outputs (turn, thrust, bite, signal, mate); type 0 rate, 1 modulatory, 2 spiking
#   src 1000..1017 is a sensor (src - 1000); hidden neuron ids are 2000 + a hash
# ------------------------------------------------------------
fun rand_body(k) {
    if (k >= n_loci) { [] }
    else {
        v = if (k == 5) { rndf() * 0.4 } else { if (k == 11) { rndf() * 0.08 } else { lo(k) + rndf() * (hi(k) - lo(k)) } }
        [[v, 0.2 + rndf() * 0.8] | rand_body(k + 1)]
    }
}

fun out_neurons(k) { if (k >= n_out) { [] } else { [[k, 0, gauss() * 0.3, 1.0 + rndf() * 1.5] | out_neurons(k + 1)] } }

fun rand_conns(k) {
    if (k <= 0) { [] }
    else { [[1000 + rndi(n_sens), rndi(n_out), gauss() * 1.5] | rand_conns(k - 1)] }
}

fun random_hap() { %{b: rand_body(0), n: out_neurons(0), c: rand_conns(9), m: rand_morph(2 + rndi(3), [])} }

fun wrap_hue(v) { if (v < 0.0) { v + 360.0 } else { if (v > 360.0) { v - 360.0 } else { v } } }

fun mut_body(lst, k, r) {
    if (length(lst) == 0) { [] }
    else {
        v = hd(hd(lst))
        d = hd(tl(hd(lst)))
        span = hi(k) - lo(k)
        v2 = if (rndf() < 0.004 * r) { lo(k) + rndf() * span }
             else { if (rndf() < 0.10 * r) { if (k == 6) { wrap_hue(v + gauss() * 0.07 * span) } else { clampf(v + gauss() * 0.07 * span, nth(FLOOR, k), nth(CEIL, k)) } } else { v } }
        d2 = if (rndf() < 0.03 * r) { clampf(d + gauss() * 0.25, 0.05, 1.0) } else { d }
        [[v2, d2] | mut_body(tl(lst), k + 1, r)]
    }
}

fun mut_neurons(lst, r) {
    if (length(lst) == 0) { [] }
    else {
        n = hd(lst)
        id = nth(n, 0)
        ty = if (id >= n_out && rndf() < 0.012 * r) { rndi(3) } else { nth(n, 1) }
        b = if (rndf() < 0.08 * r) { clampf(nth(n, 2) + gauss() * 0.4, 0.0 - 3.0, 3.0) } else { nth(n, 2) }
        t = if (rndf() < 0.05 * r) { clampf(nth(n, 3) + gauss() * 0.6, 1.0, 6.0) } else { nth(n, 3) }
        [[id, ty, b, t] | mut_neurons(tl(lst), r)]
    }
}

fun mut_conns(lst, r) {
    if (length(lst) == 0) { [] }
    else {
        c = hd(lst)
        w = nth(c, 2)
        w2 = if (rndf() < 0.01 * r) { gauss() * 2.0 } else { if (rndf() < 0.12 * r) { clampf(w + gauss() * 0.5, 0.0 - 4.0, 4.0) } else { w } }
        [[nth(c, 0), nth(c, 1), w2] | mut_conns(tl(lst), r)]
    }
}

fun find_n(lst, id) { if (length(lst) == 0) { nil } else { if (hd(hd(lst)) == id) { hd(lst) } else { find_n(tl(lst), id) } } }
fun find_c(lst, s, d) {
    if (length(lst) == 0) { nil }
    else { c = hd(lst)  if (hd(c) == s && nth(c, 1) == d) { c } else { find_c(tl(lst), s, d) } }
}
fun drop_at(lst, k) { if (length(lst) == 0) { [] } else { if (k == 0) { tl(lst) } else { [hd(lst) | drop_at(tl(lst), k - 1)] } } }

fun add_conn(h) {
    ns = g(h, 'n')
    src = if (rndf() < 0.6) { 1000 + rndi(n_sens) } else { hd(nth(ns, rndi(length(ns)))) }
    dst = hd(nth(ns, rndi(length(ns))))
    if (length(g(h, 'c')) >= cmax || find_c(g(h, 'c'), src, dst) != nil) { h } else { p(h, 'c', [[src, dst, gauss()] | g(h, 'c')]) }
}

fun del_conn(h) {
    cs = g(h, 'c')
    if (length(cs) <= 1) { h } else { p(h, 'c', drop_at(cs, rndi(length(cs)))) }
}

# split a synapse with a new neuron; its id is a hash of the synapse, so the same
# innovation in two lineages gets the same id and lines up at crossover
fun add_neuron(h) {
    cs = g(h, 'c')
    if (length(cs) == 0) { h }
    else {
        k = rndi(length(cs))
        c = nth(cs, k)
        nid = 2000 + hsh(nth(c, 0), nth(c, 1)) % 1000000
        if (find_n(g(h, 'n'), nid) != nil) { h }
        else {
            r = rndf()
            ty = if (r < 0.65) { 0 } else { if (r < 0.82) { 1 } else { 2 } }
            n2 = app(g(h, 'n'), [[nid, ty, 0.0, 1.0 + rndf() * 2.0]])
            c2 = [[nth(c, 0), nid, 1.0], [nid, nth(c, 1), nth(c, 2)] | drop_at(cs, k)]
            %{b: g(h, 'b'), n: n2, c: c2, m: g(h, 'm')}
        }
    }
}

fun mutate_hap(h, r) {
    h1 = %{b: mut_body(g(h, 'b'), 0, r), n: mut_neurons(g(h, 'n'), r), c: mut_conns(g(h, 'c'), r), m: mutate_morph(list_or_empty(g(h, 'm')), r)}
    h2 = if (rndf() < 0.22 * r) { add_conn(h1) } else { h1 }
    h3 = if (rndf() < 0.07 * r) { del_conn(h2) } else { h2 }
    if (rndf() < 0.06 * r && length(g(h3, 'n')) < nmax) { add_neuron(h3) } else { h3 }
}

# ---- meiosis: a gamete takes body loci from one haplotype, switching with
# probability 0.15 between neighbouring loci (genetic linkage) ----
fun gam_body(a, b, side) {
    if (length(a) == 0) { [] }
    else {
        s2 = if (rndf() < 0.15) { 1 - side } else { side }
        [if (s2 == 0) { hd(a) } else { hd(b) } | gam_body(tl(a), tl(b), s2)]
    }
}

# brain genes: a gene in both copies -> one allele at random; in one copy only
# (heterozygous presence) -> passed on half the time; outputs always kept
fun gam_neurons(as, bs) {
    if (length(as) == 0) { [] }
    else {
        x = hd(as)
        y = find_n(bs, hd(x))
        keep = if (y != nil) { if (rndf() < 0.5) { x } else { y } } else { if (hd(x) < n_out || rndf() < 0.5) { x } else { nil } }
        rest = gam_neurons(tl(as), bs)
        if (keep == nil) { rest } else { [keep | rest] }
    }
}

fun only_in(bs, as, is_conn) {
    if (length(bs) == 0) { [] }
    else {
        y = hd(bs)
        found = if (is_conn) { find_c(as, hd(y), nth(y, 1)) } else { find_n(as, hd(y)) }
        rest = only_in(tl(bs), as, is_conn)
        if (found == nil && rndf() < 0.5) { [y | rest] } else { rest }
    }
}

fun gam_conns(as, bs) {
    if (length(as) == 0) { [] }
    else {
        x = hd(as)
        y = find_c(bs, hd(x), nth(x, 1))
        keep = if (y != nil) { if (rndf() < 0.5) { x } else { y } } else { if (rndf() < 0.5) { x } else { nil } }
        rest = gam_conns(tl(as), bs)
        if (keep == nil) { rest } else { [keep | rest] }
    }
}

fun gamete(a, b, rate) {
    ns = app(gam_neurons(g(a, 'n'), g(b, 'n')), only_in(g(b, 'n'), g(a, 'n'), false))
    cs = app(gam_conns(g(a, 'c'), g(b, 'c')), only_in(g(b, 'c'), g(a, 'c'), true))
    ns2 = if (length(ns) > nmax) { Std.take(ns, nmax) } else { ns }
    cs2 = if (length(cs) > cmax) { Std.take(cs, cmax) } else { cs }
    ms = app(gam_neurons(list_or_empty(g(a, 'm')), list_or_empty(g(b, 'm'))), only_in(list_or_empty(g(b, 'm')), list_or_empty(g(a, 'm')), false))
    mutate_hap(%{b: gam_body(g(a, 'b'), g(b, 'b'), rndi(2)), n: ns2, c: cs2, m: ms}, rate)
}

# ---- expression: genotype -> phenotype ----
fun expr_body(a, b, k) {
    if (length(a) == 0) { [] }
    else {
        va = hd(hd(a))
        da = hd(tl(hd(a)))
        vb = hd(hd(b))
        db = hd(tl(hd(b)))
        v = if (k == 6 && fabs(va - vb) > 180.0) { wrap_hue((da * va + db * (vb + (if (vb < va) { 360.0 } else { 0.0 - 360.0 }))) / (da + db)) }
            else { (da * va + db * vb) / (da + db + 0.000001) }
        [v | expr_body(tl(a), tl(b), k + 1)]
    }
}

fun expr_neurons(as, bs) {
    if (length(as) == 0) { only_all(bs, []) }
    else {
        x = hd(as)
        y = find_n(bs, hd(x))
        e = if (y == nil) { x } else { [hd(x), nth(x, 1), (nth(x, 2) + nth(y, 2)) / 2.0, (nth(x, 3) + nth(y, 3)) / 2.0] }
        [e | expr_neurons(tl(as), remove_n(bs, hd(x)))]
    }
}
fun remove_n(lst, id) { if (length(lst) == 0) { [] } else { if (hd(hd(lst)) == id) { tl(lst) } else { [hd(lst) | remove_n(tl(lst), id)] } } }
fun only_all(bs, acc) { app(bs, acc) }

fun expr_conns(as, bs) {
    if (length(as) == 0) { bs }
    else {
        x = hd(as)
        y = find_c(bs, hd(x), nth(x, 1))
        e = if (y == nil) { x } else { [hd(x), nth(x, 1), (nth(x, 2) + nth(y, 2)) / 2.0] }
        [e | expr_conns(tl(as), remove_c(bs, hd(x), nth(x, 1)))]
    }
}
fun remove_c(lst, s, d) {
    if (length(lst) == 0) { [] }
    else { c = hd(lst)  if (hd(c) == s && nth(c, 1) == d) { tl(lst) } else { [c | remove_c(tl(lst), s, d)] } }
}

# outputs first (local 0..4), hidden after, capped
fun order_neurons(ns) {
    outs = order_outs(ns, 0)
    hid = hidden_of(ns)
    all = app(outs, hid)
    if (length(all) > nmax) { Std.take(all, nmax) } else { all }
}
fun order_outs(ns, k) { if (k >= n_out) { [] } else { n = find_n(ns, k)  [if (n == nil) { [k, 0, 0.0, 1.0] } else { n } | order_outs(ns, k + 1)] } }
fun hidden_of(ns) { if (length(ns) == 0) { [] } else { if (hd(hd(ns)) >= n_out) { [hd(ns) | hidden_of(tl(ns))] } else { hidden_of(tl(ns)) } } }

fun idx_of(ns, id, k) { if (length(ns) == 0) { -1 } else { if (hd(hd(ns)) == id) { k } else { idx_of(tl(ns), id, k + 1) } } }

# keep only synapses whose ends exist in this body
fun live_conns(cs, ns) { rev(live_acc(cs, ns, []), []) }
fun live_acc(cs, ns, acc) {
    if (length(cs) == 0) { acc }
    else {
        c = hd(cs)
        ok = idx_of(ns, nth(c, 1), 0) >= 0 && (is_sens(hd(c)) || idx_of(ns, hd(c), 0) >= 0)
        live_acc(tl(cs), ns, if (ok) { [c | acc] } else { acc })
    }
}

# genetic distance on the body loci 0..9 (morphology, colour, pattern)
fun body_dist(p1, p2, k) {
    if (k >= 10) { 0.0 }
    else {
        a = nth(p1, k)
        b = nth(p2, k)
        d = if (k == 6) { hue_gap(a, b) / 180.0 } else { fabs(a - b) / (hi(k) - lo(k)) }
        d + body_dist(p1, p2, k + 1)
    }
}

# ------------------------------------------------------------
# Neurons: each is a process. It keeps its own incoming synapses
# [key, kind, w] (key = local source or 1000+sensor; kind 1 = modulatory source),
# integrates what arrived since the last tick, fires, learns, and reports.
# ------------------------------------------------------------
fun neuron(cfg, inl) {
    receive {
        {'wire', pids} -> neuron_loop(cfg, inl, out_pids(elem(cfg, 5), pids), 0.0, 0.0, [], 0)
        {'stop'} -> 'ok'
    }
}

fun out_pids(outs, pids) { if (length(outs) == 0) { [] } else { [nth(pids, hd(outs)) | out_pids(tl(outs), pids)] } }

# cfg = {slot, li, type, bias, tau, outs, plast [eta A B C D m0], tab, world}
fun neuron_loop(cfg, w, outp, a, v, ins, cnt) {
    receive {
        {'in', src, x} -> neuron_loop(cfg, w, outp, a, v, [{src, x} | ins], cnt)
        {'tick', sens, plast} ->
            pres = pre_vals(w, sens, ins)
            xm = sum_in(w, pres, 0.0, 0.0)
            ty = elem(cfg, 2)
            tau = elem(cfg, 4)
            x = elem(xm, 0) + elem(cfg, 3)
            spike = ty == 2 && v * (1.0 - 1.0 / tau) + x >= 1.0
            a2 = if (ty == 2) { if (spike) { 1.0 } else { 0.0 } } else { a + (tanh(x) - a) / tau }
            v2 = if (ty == 2) { if (spike) { 0.0 } else { fmax(0.0 - 1.0, v * (1.0 - 1.0 / tau) + x) } } else { 0.0 }
            pl = elem(cfg, 6)
            eta = hd(pl)
            w2 = if (plast == 1 && eta > 0.002) {
                mod = tanh(nth(pl, 5) + elem(xm, 1))
                learn(w, pres, a2, eta * mod, nth(pl, 1), nth(pl, 2), nth(pl, 3), nth(pl, 4))
            } else { w }
            send_outs(outp, elem(cfg, 1), a2)
            gid = elem(cfg, 0) * nmax + elem(cfg, 1)
            tab = elem(cfg, 7)
            tput(tab, k_act + gid, a2)
            if (cnt % 16 == 0) { tput(tab, k_w + gid, w2) } else { 'x' }
            send(elem(cfg, 8), {'a'})
            neuron_loop(cfg, w2, outp, a2, v2, [], cnt + 1)
        {'stop'} -> 'ok'
    }
}

fun lookup(ins, src) {
    if (length(ins) == 0) { 0.0 }
    else { if (elem(hd(ins), 0) == src) { elem(hd(ins), 1) } else { lookup(tl(ins), src) } }
}

fun pre_vals(w, sens, ins) {
    if (length(w) == 0) { [] }
    else {
        k = hd(hd(w))
        [if (k >= 1000) { nth(sens, k - 1000) } else { lookup(ins, k) } | pre_vals(tl(w), sens, ins)]
    }
}

fun sum_in(w, pres, x, m) {
    if (length(w) == 0) { {x, m} }
    else {
        e = hd(w)
        c = nth(e, 2) * hd(pres)
        if (nth(e, 1) == 1) { sum_in(tl(w), tl(pres), x, m + c) } else { sum_in(tl(w), tl(pres), x + c, m) }
    }
}

# the evolved learning rule, gated by neuromodulation
fun learn(w, pres, post, rate, ca, cb, cc, cd) {
    if (length(w) == 0) { [] }
    else {
        e = hd(w)
        pre = hd(pres)
        dw = rate * (ca * pre * post + cb * pre + cc * post + cd)
        [[hd(e), nth(e, 1), clampf(nth(e, 2) + dw, 0.0 - 4.0, 4.0)] | learn(tl(w), tl(pres), post, rate, ca, cb, cc, cd)]
    }
}

fun send_outs(outp, li, a) {
    if (length(outp) == 0) { 'ok' } else { send(hd(outp), {'in', li, a})  send_outs(tl(outp), li, a) }
}

# ---- building a brain from a phenotype: spawn one process per neuron, then wire them ----
fun in_list(cs, ns, id) { rev(in_acc(cs, ns, id, []), []) }
fun in_acc(cs, ns, id, acc) {
    if (length(cs) == 0) { acc }
    else {
        c = hd(cs)
        if (nth(c, 1) == id) {
            s = hd(c)
            key = if (is_sens(s)) { s } else { idx_of(ns, s, 0) }
            kind = if (is_sens(s) == false && nth(find_n(ns, s), 1) == 1) { 1 } else { 0 }
            in_acc(tl(cs), ns, id, [[key, kind, nth(c, 2)] | acc])
        } else { in_acc(tl(cs), ns, id, acc) }
    }
}

fun out_list(cs, ns, id) { rev(out_acc(cs, ns, id, []), []) }
fun out_acc(cs, ns, id, acc) {
    if (length(cs) == 0) { acc }
    else { c = hd(cs)  out_acc(tl(cs), ns, id, if (hd(c) == id) { [idx_of(ns, nth(c, 1), 0) | acc] } else { acc }) }
}

fun spawn_neurons(tab, world, slot, ns, cs, all, pl, li) {
    if (length(ns) == 0) { [] }
    else {
        n = hd(ns)
        id = hd(n)
        cfg = {slot, li, nth(n, 1), nth(n, 2), nth(n, 3), out_list(cs, all, id), pl, tab, world}
        inl = in_list(cs, all, id)
        pid = spawn(neuron(cfg, inl))
        [pid | spawn_neurons(tab, world, slot, tl(ns), cs, all, pl, li + 1)]
    }
}

fun send_all(pids, msg) { if (length(pids) == 0) { 'ok' } else { send(hd(pids), msg)  send_all(tl(pids), msg) } }

fun in_lists(cs, ns, all) { if (length(ns) == 0) { [] } else { [in_list(cs, all, hd(hd(ns))) | in_lists(cs, tl(ns), all)] } }

# ------------------------------------------------------------
# Creatures
# ------------------------------------------------------------
fun phenotype(ha, hb) {
    ph = expr_body(g(ha, 'b'), g(hb, 'b'), 0)
    ns = order_neurons(expr_neurons(g(ha, 'n'), g(hb, 'n')))
    cs = live_conns(expr_conns(g(ha, 'c'), g(hb, 'c')), ns)
    {ph, ns, cs}
}

fun make_creature(tab, world, s, ha, hb, slot, gen, sp, x, y, e, mom, dad) {
    pt = phenotype(ha, hb)
    ph = elem(pt, 0)
    ns = elem(pt, 1)
    cs = elem(pt, 2)
    pl = [nth(ph, 11), nth(ph, 12), nth(ph, 13), nth(ph, 14), nth(ph, 15), nth(ph, 16)]
    pids = spawn_neurons(tab, world, slot, ns, cs, ns, pl, 0)
    send_all(pids, {'wire', pids})
    a = rndf() * 6.2832
    genes = expr_morph(list_or_empty(g(ha, 'm')), list_or_empty(g(hb, 'm')))
    spec = build_spec(ph, genes)
    st = body_stats(spec)
    nodes = layout(spec, x, y, Math.cos(a), Math.sin(a))
    %{spec: spec, nodes: nodes, mass: elem(st, 0), perim: elem(st, 1), nnodes: length(spec), hits: 0.0,
      pw: elem(st, 7) * 100.0 * fmax(0.0, nth(ph, 3)), sight: fmax(0.05, nth(ph, 4)) + elem(st, 6) * 12.0,
      nspk: elem(st, 2), narm: elem(st, 3), nfin: elem(st, 4), nmou: elem(st, 5), nmus: elem(st, 8),
      id: g(s, 'next_id'), slot: slot, gen: gen, sp: sp, ha: ha, hb: hb, ph: ph,
      types: types_of(ns), inl: in_lists(cs, ns, ns), pids: pids, nn: length(ns), nc: length(cs),
      x: x, y: y, hx: Math.cos(a), hy: Math.sin(a), e: e, h: 100.0, age: 0, life: 1300 + rndi(700),
      cool: 160, acd: 0, kids: 0, kills: 0, eaten: 0, pain: 0, sig: 0.0, bite: 0, mate: 0, outs: [0.0, 0.0, 0.0, 0.0, 0.0],
      sv: [], mom: mom, dad: dad, killer: 0, vk: g(s, 'vk'), isl: g(s, 'isl')}
}

fun types_of(ns) { if (length(ns) == 0) { [] } else { [nth(hd(ns), 1) | types_of(tl(ns))] } }

fun kill_brain(c) { send_all(g(c, 'pids'), {'stop'}) }

fun founder_genome() {
    a = random_hap()
    {a, mutate_hap(a, 1.0)}
}

# ------------------------------------------------------------
# Bodies: a genome grows a tree of nodes. Each morph gene is
#   [id, parent id, angle, length, radius, type, muscle, phase]
# type 0 body, 1 spike, 2 armor, 3 fin, 4 mouth, 5 eye (the core, id 0, is implicit).
# A muscle gene makes its node flap around its rest angle, driven by a rhythm (the
# frequency and strength genes) that the brain modulates: thrust sets the stroke,
# turn makes the left and right strokes unequal. Fins drag strongly across and weakly
# along their link, so a flapping fin can push the body; nothing else makes it move.
# ------------------------------------------------------------
let max_nodes = 64

fun rand_type() {
    r = rndf()
    if (r < 0.30) { 0 } else { if (r < 0.45) { 3 } else { if (r < 0.58) { 1 } else { if (r < 0.70) { 2 } else { if (r < 0.85) { 4 } else { 5 } } } } }
}

fun new_mgene(parent, k) {
    [1000 + rndi(9000000), parent, (rndf() - 0.5) * 6.2832, 0.022 + rndf() * 0.02, 0.006 + rndf() * 0.008, rand_type(), if (rndf() < 0.5) { 1 } else { 0 }, rndf() * 6.2832]
}

fun rand_morph(k, acc) {
    if (k <= 0) { acc }
    else {
        parent = if (length(acc) > 0 && rndf() < 0.4) { hd(nth(acc, rndi(length(acc)))) } else { 0 }
        rand_morph(k - 1, [new_mgene(parent, k) | acc])
    }
}

fun mut_mgene(gn, r) {
    ang = if (rndf() < 0.10 * r) { nth(gn, 2) + gauss() * 0.3 } else { nth(gn, 2) }
    len = if (rndf() < 0.10 * r) { fmax(0.012, nth(gn, 3) * (1.0 + gauss() * 0.12)) } else { nth(gn, 3) }
    rad = if (rndf() < 0.10 * r) { fmax(0.004, nth(gn, 4) * (1.0 + gauss() * 0.12)) } else { nth(gn, 4) }
    ty = if (rndf() < 0.02 * r) { rand_type() } else { nth(gn, 5) }
    mu = if (rndf() < 0.03 * r) { 1 - nth(gn, 6) } else { nth(gn, 6) }
    ph = if (rndf() < 0.08 * r) { nth(gn, 7) + gauss() * 0.7 } else { nth(gn, 7) }
    [hd(gn), nth(gn, 1), ang, len, rad, ty, mu, ph]
}
fun mut_mgenes(lst, r, acc) { if (length(lst) == 0) { rev(acc, []) } else { mut_mgenes(tl(lst), r, [mut_mgene(hd(lst), r) | acc]) } }

fun is_parent(lst, id) { if (length(lst) == 0) { false } else { if (nth(hd(lst), 1) == id) { true } else { is_parent(tl(lst), id) } } }
fun leaves(all, lst, acc) { if (length(lst) == 0) { acc } else { leaves(all, tl(lst), if (is_parent(all, hd(hd(lst)))) { acc } else { [hd(hd(lst)) | acc] }) } }
fun remove_m(lst, id, acc) { if (length(lst) == 0) { rev(acc, []) } else { remove_m(tl(lst), id, if (hd(hd(lst)) == id) { acc } else { [hd(lst) | acc] }) } }

fun mutate_morph(m, r) {
    m1 = mut_mgenes(m, r, [])
    m2 = if (rndf() < 0.10 * r && length(m1) < max_nodes) {
        parent = if (length(m1) > 0 && rndf() < 0.6) { hd(nth(m1, rndi(length(m1)))) } else { 0 }
        app(m1, [new_mgene(parent, length(m1))])
    } else { m1 }
    lv = leaves(m2, m2, [])
    if (rndf() < 0.05 * r && length(lv) > 0 && length(m2) > 1) { remove_m(m2, nth(lv, rndi(length(lv))), []) } else { m2 }
}

# expression: both copies' node genes, matched by id (numbers averaged), then only the nodes
# connected to the core, parents before children
fun expr_morph(as, bs) {
    u = expr_m_union(as, bs, [])
    bfs(u, [0], [])
}
fun expr_m_union(as, bs, acc) {
    if (length(as) == 0) { app(rev(acc, []), bs) }
    else {
        x = hd(as)
        y = find_n(bs, hd(x))
        e = if (y == nil) { x } else { [hd(x), nth(x, 1), (nth(x, 2) + nth(y, 2)) / 2.0, (nth(x, 3) + nth(y, 3)) / 2.0, (nth(x, 4) + nth(y, 4)) / 2.0, nth(x, 5), nth(x, 6), (nth(x, 7) + nth(y, 7)) / 2.0] }
        expr_m_union(tl(as), remove_n(bs, hd(x)), [e | acc])
    }
}
fun bfs(all, frontier, acc) {
    if (length(frontier) == 0 || length(acc) >= max_nodes) { acc }
    else {
        nxt = children_of(all, frontier, acc, [])
        room = max_nodes - length(acc)
        nxt2 = if (length(nxt) > room) { Std.take(nxt, room) } else { nxt }
        bfs(all, ids_of_m(nxt2, []), app(acc, nxt2))
    }
}
fun children_of(all, frontier, have, acc) {
    if (length(all) == 0) { rev(acc, []) }
    else {
        gn = hd(all)
        ok = member(frontier, nth(gn, 1)) && find_n(have, hd(gn)) == nil && find_n(acc, hd(gn)) == nil
        children_of(tl(all), frontier, have, if (ok) { [gn | acc] } else { acc })
    }
}
fun member(lst, v) { if (length(lst) == 0) { false } else { if (hd(lst) == v) { true } else { member(tl(lst), v) } } }
fun ids_of_m(lst, acc) { if (length(lst) == 0) { acc } else { ids_of_m(tl(lst), [hd(hd(lst)) | acc]) } }

# ---- the physical body ----
# spec per node: {radius, type, parent index, rest length, muscle, phase, side, rest angle}; index 0 is the core
fun core_r(ph) { 0.010 * fmax(0.3, hd(ph)) }
fun build_spec(ph, genes) {
    sc = fmax(0.3, hd(ph))
    rev(bs_acc(genes, genes, [{core_r(ph), 6, 0 - 1, 0.0, 0, 0.0, 0.0, 0.0}], [0], sc), [])
}
# acc is the spec list built so far (reversed); ids holds the gene id of each index (reversed)
fun bs_acc(all, lst, acc, ids, sc) {
    if (length(lst) == 0) { acc }
    else {
        gn = hd(lst)
        n = length(acc)
        pidx = idx_rev(ids, nth(gn, 1), n - 1)
        pang = if (pidx <= 0) { 0.0 } else { elem(nth(rev(acc, []), pidx), 7) }
        a0 = pang + nth(gn, 2)
        side = if (Math.sin(a0) > 0.05) { 1.0 } else { if (Math.sin(a0) < 0.0 - 0.05) { 0.0 - 1.0 } else { 0.0 } }
        bs_acc(all, tl(lst), [{nth(gn, 4) * sc, nth(gn, 5), if (pidx < 0) { 0 } else { pidx }, nth(gn, 3) * sc, nth(gn, 6), nth(gn, 7), side, a0} | acc], [hd(gn) | ids], sc)
    }
}
# index of gene id in the reversed id list (k is the index of the head)
fun idx_rev(ids, id, k) { if (length(ids) == 0) { 0 - 1 } else { if (hd(ids) == id) { k } else { idx_rev(tl(ids), id, k - 1) } } }

fun rot(c, s, a) { {c * Math.cos(a) - s * Math.sin(a), s * Math.cos(a) + c * Math.sin(a)} }

# lay the body out at (x, y) facing (hx, hy)
fun layout(spec, x, y, hx, hy) { rev(lay_acc(spec, x, y, hx, hy, []), []) }
fun lay_acc(spec, x, y, hx, hy, acc) {
    if (length(spec) == 0) { acc }
    else {
        sp = hd(spec)
        n = length(acc)
        pos = if (n == 0) { {x, y} } else {
            pn = nth(rev(acc, []), elem(sp, 2))
            d = rot(hx, hy, elem(sp, 7))
            {elem(pn, 0) + elem(d, 0) * elem(sp, 3), elem(pn, 1) + elem(d, 1) * elem(sp, 3)}
        }
        lay_acc(tl(spec), x, y, hx, hy, [{clampw(elem(pos, 0)), clampw(elem(pos, 1)), 0.0, 0.0} | acc])
    }
}

fun mass_of(r) { 1.0 + 6000.0 * r * r }

fun body_stats(spec) { bstat(spec, 0.0, 0.0, 0, 0, 0, 0, 0.0, 0.0, 0) }
# -> {mass units, perimeter units, spikes, armor, fins, mouths, eye radius sum, spike radius sum, muscles}
fun bstat(spec, m, per, sp, ar, fi, mo, eye, spr, mu) {
    if (length(spec) == 0) { {m, per, sp, ar, fi, mo, eye, spr, mu} }
    else {
        s0 = hd(spec)
        r = elem(s0, 0) / 0.010
        t = elem(s0, 1)
        bstat(tl(spec), m + r * r, per + r, sp + (if (t == 1) { 1 } else { 0 }), ar + (if (t == 2) { 1 } else { 0 }), fi + (if (t == 3) { 1 } else { 0 }),
              mo + (if (t == 4) { 1 } else { 0 }), eye + (if (t == 5) { elem(s0, 0) } else { 0.0 }), spr + (if (t == 1) { elem(s0, 0) } else { 0.0 }),
              mu + (if (elem(s0, 4) == 1) { 1 } else { 0 }))
    }
}

# ---- one physics step for one creature: muscles, shape springs, body rotation, drag, integration ----
# The body has its own heading and angular velocity: a muscle pulling a limb one way twists the
# body the other way (torque / moment of inertia), the way a swimmer's body yaws with each stroke.
# returns {nodes, hx, hy, work, om}
fun physics(spec, nodes, hx, hy, om, ph, thrust, turn, tick, slowk, obs, mass) {
    freq = fmax(0.1, nth(ph, 1))
    w = 0.35 * freq
    stren = fmax(0.0, nth(ph, 2))
    # cilia: a small push along the body axis and a small turning torque, weaker for heavy bodies
    cil = 1.0 / (1.0 + 0.08 * fmax(1.0, mass))
    nodes0 = push_core(nodes, hx * 0.0007 * thrust * cil / slowk, hy * 0.0007 * thrust * cil / slowk)
    phys_sub(spec, nodes0, hx, hy, om + 0.015 * turn * cil, w, freq, stren, thrust, turn, tick, slowk, obs, 2, 0.0)
}
fun phys_sub(spec, nodes, hx, hy, om, w, freq, stren, thrust, turn, tick, slowk, obs, k, work) {
    if (k <= 0) { {nodes, hx, hy, work, om} }
    else {
        t = to_float(tick) + (if (k == 1) { 0.5 } else { 0.0 })
        acts = muscle_acts(spec, w, t, stren, thrust, turn, [])
        ft = forces(spec, nodes, acts, hx, hy, 0, zero_v(length(nodes), []), 0.0, 0.0001)
        om2 = (om + elem(ft, 1) / elem(ft, 2)) * (1.0 - 0.3 * slowk)
        hh = rot(hx, hy, om2)
        hl = Math.sqrt(elem(hh, 0) * elem(hh, 0) + elem(hh, 1) * elem(hh, 1)) + 0.000001
        bc = elem(hh, 0) / hl
        bs = elem(hh, 1) / hl
        nodes2 = integrate(spec, nodes, elem(ft, 0), slowk, obs, bc, bs, 0, [])
        phys_sub(spec, nodes2, bc, bs, om2, w, freq, stren, thrust, turn, tick, slowk, obs, k - 1, work + sum_abs(acts, 0.0) * stren * freq * 0.0012)
    }
}
fun push_core(nodes, dvx, dvy) { n = hd(nodes)  [{elem(n, 0), elem(n, 1), elem(n, 2) + dvx, elem(n, 3) + dvy} | tl(nodes)] }
fun zero_v(n, acc) { if (n <= 0) { acc } else { zero_v(n - 1, [{0.0, 0.0} | acc]) } }
fun sum_abs(l, a) { if (length(l) == 0) { a } else { sum_abs(tl(l), a + fabs(hd(l))) } }

# a muscle flaps its node: offset = 0.7 * strength * drive * sin(w t + phase); drive = thrust, plus or minus turn by side
fun muscle_acts(spec, w, t, stren, thrust, turn, acc) {
    if (length(spec) == 0) { rev(acc, []) }
    else {
        sp = hd(spec)
        drive = clampf(0.3 + thrust + turn * elem(sp, 6) * 0.8, 0.0 - 1.3, 1.3)
        a = if (elem(sp, 4) == 1) { 1.3 * fmin(2.0, stren) * drive * Math.sin(w * t + elem(sp, 5)) } else { 0.0 }
        muscle_acts(tl(spec), w, t, stren, thrust, turn, [a | acc])
    }
}

fun add_at(l, k, fx, fy) { if (k == 0) { v = hd(l)  [{elem(v, 0) + fx, elem(v, 1) + fy} | tl(l)] } else { [hd(l) | add_at(tl(l), k - 1, fx, fy)] } }

fun forces(spec, nodes, acts, bc, bs, i, fs, tau, inert) {
    if (length(spec) == 0) { {fs, tau, inert} }
    else {
        sp = hd(spec)
        if (i == 0) { forces(tl(spec), nodes, acts, bc, bs, 1, fs, tau, inert) }
        else {
            pi = elem(sp, 2)
            pn = nth(nodes, pi)
            me = nth(nodes, i)
            core = hd(nodes)
            d = rot(bc, bs, elem(sp, 7) + nth(acts, i))
            tx = elem(pn, 0) + elem(d, 0) * elem(sp, 3)
            ty = elem(pn, 1) + elem(d, 1) * elem(sp, 3)
            fx = 0.30 * (tx - elem(me, 0))
            fy = 0.30 * (ty - elem(me, 1))
            rx = elem(me, 0) - elem(core, 0)
            ry = elem(me, 1) - elem(core, 1)
            m = mass_of(elem(sp, 0))
            forces(tl(spec), nodes, acts, bc, bs, i + 1, add_at(add_at(fs, i, fx, fy), pi, 0.0 - fx, 0.0 - fy),
                   tau - (rx * fy - ry * fx), inert + m * (rx * rx + ry * ry))
        }
    }
}

fun integrate(spec, nodes, fs, slowk, obs, hx, hy, i, acc) {
    if (length(spec) == 0) { rev(acc, []) }
    else {
        sp = hd(spec)
        nd = hd(nodes)
        f = hd(fs)
        m = mass_of(elem(sp, 0))
        vx0 = elem(nd, 2) + elem(f, 0) / m
        vy0 = elem(nd, 3) + elem(f, 1) / m
        # drag: fins drag hard across their link and lightly along it; everything else evenly
        v = if (elem(sp, 1) == 3 && i > 0) { fin_drag(vx0, vy0, nd, nth(rev(acc, []), elem(sp, 2)), slowk, hx, hy) } else { {vx0 * (1.0 - 0.04 * slowk), vy0 * (1.0 - 0.04 * slowk)} }
        x = elem(nd, 0) + elem(v, 0)
        y = elem(nd, 1) + elem(v, 1)
        po = push_out(clampw(x), clampw(y), obs)
        integrate(tl(spec), tl(nodes), tl(fs), slowk, obs, hx, hy, i + 1, [{elem(po, 0), elem(po, 1), elem(v, 0), elem(v, 1)} | acc])
    }
}
# a fin feathers like an oar: its sideways (across-the-link) motion is resisted hard when it sweeps
# backward (the power stroke) and only lightly when it swings forward (the recovery)
fun fin_drag(vx, vy, nd, pn, slowk, hx, hy) {
    lx = elem(nd, 0) - elem(pn, 0)
    ly = elem(nd, 1) - elem(pn, 1)
    l = Math.sqrt(lx * lx + ly * ly) + 0.000001
    ux = lx / l
    uy = ly / l
    vpar = vx * ux + vy * uy
    px = vx - vpar * ux
    py = vy - vpar * uy
    back = (px * hx + py * hy) < 0.0
    kp = fmin(0.95, (if (back) { 0.7 } else { 0.08 }) * slowk)
    ka = fmin(0.95, 0.05 * slowk)
    {vpar * (1.0 - ka) * ux + px * (1.0 - kp), vpar * (1.0 - ka) * uy + py * (1.0 - kp)}
}

# move a whole body (collisions push bodies apart)
fun shift_nodes(nodes, dx, dy, acc) { if (length(nodes) == 0) { rev(acc, []) } else { n = hd(nodes)  shift_nodes(tl(nodes), dx, dy, [{clampw(elem(n, 0) + dx), clampw(elem(n, 1) + dy), elem(n, 2), elem(n, 3)} | acc]) } }

# ------------------------------------------------------------
# Contact physics between bodies (a 20 x 20 grid of node cells):
#   overlapping nodes of two creatures push the bodies apart;
#   a spike that hits a stranger's node does damage that grows with impact speed,
#   divided by 3 if it hits an armor node. The attacker's bite output scales it (0.25 .. 1.25).
# ------------------------------------------------------------
fun ncell(v) { k = to_int(v / 0.08)  if (k < 0) { 0 } else { if (k > 19) { 19 } else { k } } }

# node tuples: {x, y, vx, vy, r, type, creature id, species, bite, sharpness, diet}
fun node_tuples(crs, acc) { if (length(crs) == 0) { acc } else { node_tuples(tl(crs), nt_one(hd(crs), g(hd(crs), 'nodes'), g(hd(crs), 'spec'), acc)) } }
fun nt_one(c, nodes, spec, acc) {
    if (length(nodes) == 0) { acc }
    else {
        n = hd(nodes)
        sp = hd(spec)
        nt_one(c, tl(nodes), tl(spec), [{elem(n, 0), elem(n, 1), elem(n, 2), elem(n, 3), elem(sp, 0), elem(sp, 1), g(c, 'id'), g(c, 'sp'),
              0.25 + fmax(0.0, numf(nth(g(c, 'outs'), 2))), fmax(0.0, nth(g(c, 'ph'), 3)), nth(g(c, 'ph'), 5)} | acc])
    }
}
fun nbuild(lst, m) {
    if (length(lst) == 0) { m }
    else { t = hd(lst)  k = ncell(elem(t, 1)) * 20 + ncell(elem(t, 0))  nbuild(tl(lst), map_put(m, k, [t | list_or_empty(map_get(m, k))])) }
}

# every touching pair (each pair once: the lower creature id handles it) -> {pushes, hits}
#   pushes: [{id, dx, dy}], hits: [{attacker, target, damage}]
fun contacts(nodes, grid) { ct_nodes(nodes, grid, [], []) }
fun ct_nodes(lst, grid, push, hits) {
    if (length(lst) == 0) { {push, hits} }
    else {
        a = hd(lst)
        cx = ncell(elem(a, 0))
        cy = ncell(elem(a, 1))
        r = ct_cells(a, grid, ring(0), cx, cy, push, hits)
        r2 = ct_cells(a, grid, ring(1), cx, cy, elem(r, 0), elem(r, 1))
        ct_nodes(tl(lst), grid, elem(r2, 0), elem(r2, 1))
    }
}
fun ct_cells(a, grid, offs, cx, cy, push, hits) {
    if (length(offs) == 0) { {push, hits} }
    else {
        o = hd(offs)
        gx = cx + elem(o, 0)
        gy = cy + elem(o, 1)
        r = if (gx < 0 || gy < 0 || gx > 19 || gy > 19) { {push, hits} } else { ct_items(a, list_or_empty(map_get(grid, gy * 20 + gx)), push, hits) }
        ct_cells(a, grid, tl(offs), cx, cy, elem(r, 0), elem(r, 1))
    }
}
fun ct_items(a, lst, push, hits) {
    if (length(lst) == 0) { {push, hits} }
    else {
        b = hd(lst)
        if (elem(a, 6) >= elem(b, 6)) { ct_items(a, tl(lst), push, hits) }
        else {
            dx = elem(b, 0) - elem(a, 0)
            dy = elem(b, 1) - elem(a, 1)
            rr = elem(a, 4) + elem(b, 4)
            d2 = dx * dx + dy * dy
            if (d2 >= rr * rr) { ct_items(a, tl(lst), push, hits) }
            else {
                d = Math.sqrt(d2) + 0.000001
                ov = (rr - d) * 0.15
                nx = dx / d
                ny = dy / d
                p2 = [{elem(a, 6), 0.0 - nx * ov, 0.0 - ny * ov}, {elem(b, 6), nx * ov, ny * ov} | push]
                rvx = elem(a, 2) - elem(b, 2)
                rvy = elem(a, 3) - elem(b, 3)
                impact = fabs(rvx * nx + rvy * ny)
                strangers = elem(a, 7) != elem(b, 7)
                h1 = if (strangers && elem(a, 5) == 1) { [{elem(a, 6), elem(b, 6), spike_dmg(a, b, impact)} | hits] } else { hits }
                h2 = if (strangers && elem(b, 5) == 1) { [{elem(b, 6), elem(a, 6), spike_dmg(b, a, impact)} | h1] } else { h1 }
                ct_items(a, tl(lst), p2, h2)
            }
        }
    }
}
fun spike_dmg(att, tgt, impact) {
    base = (2.0 + impact * 900.0) * (elem(att, 4) / 0.010) * elem(att, 9) * elem(att, 8)
    if (elem(tgt, 5) == 2) { base / 3.0 } else { base }
}

# sum per creature: id -> {dx, dy} and id -> damage taken, id -> damage dealt
fun sum_push(lst, m) {
    if (length(lst) == 0) { m }
    else { p0 = hd(lst)  old = map_get(m, elem(p0, 0))  sum_push(tl(lst), map_put(m, elem(p0, 0), if (old == nil) { {elem(p0, 1), elem(p0, 2)} } else { {elem(old, 0) + elem(p0, 1), elem(old, 1) + elem(p0, 2)} })) }
}
fun sum_hits(lst, taken, dealt, by) {
    if (length(lst) == 0) { {taken, dealt, by} }
    else {
        h = hd(lst)
        sum_hits(tl(lst), map_put(taken, elem(h, 1), numf(map_get(taken, elem(h, 1))) + elem(h, 2)),
                 map_put(dealt, elem(h, 0), numf(map_get(dealt, elem(h, 0))) + elem(h, 2)), map_put(by, elem(h, 1), elem(h, 0)))
    }
}

fun apply_contacts(crs, pm, taken, dealt, by, acc) {
    if (length(crs) == 0) { acc }
    else {
        c = hd(crs)
        id = g(c, 'id')
        pu = map_get(pm, id)
        c1 = if (pu == nil) { c } else { cap_push(c, elem(pu, 0), elem(pu, 1)) }
        tk = numf(map_get(taken, id))
        dl = numf(map_get(dealt, id))
        c2 = if (tk > 0.0) { p(p(p(c1, 'h', g(c1, 'h') - tk), 'pain', 10), 'killer', num(map_get(by, id))) } else { c1 }
        c3 = if (dl > 0.0) { p(p(c2, 'e', fmin(100.0, g(c2, 'e') + dl * 0.5 * (0.25 + 0.75 * nth(g(c2, 'ph'), 5)))), 'hits', numf(g(c2, 'hits')) + 1.0) } else { c2 }
        apply_contacts(tl(crs), pm, taken, dealt, by, [c3 | acc])
    }
}
fun cap_push(c, dx, dy) {
    l = Math.sqrt(dx * dx + dy * dy)
    k = if (l > 0.004) { 0.004 / l } else { 1.0 }
    nodes = shift_nodes(g(c, 'nodes'), dx * k, dy * k, [])
    p(p(p(c, 'nodes', nodes), 'x', elem(hd(nodes), 0)), 'y', elem(hd(nodes), 1))
}

fun contact_step(crs) {
    nodes = node_tuples(crs, [])
    r = contacts(nodes, nbuild(nodes, %{}))
    hs = sum_hits(elem(r, 1), %{}, %{}, %{})
    apply_contacts(crs, sum_push(elem(r, 0), %{}), elem(hs, 0), elem(hs, 1), elem(hs, 2), [])
}

# mouths (and the core) eat: each eating point is {x, y, reach}
fun mouths(c) { mo_acc(g(c, 'nodes'), g(c, 'spec'), 0, []) }
fun mo_acc(nodes, spec, i, acc) {
    if (length(nodes) == 0) { acc }
    else {
        n = hd(nodes)
        sp = hd(spec)
        eats = i == 0 || elem(sp, 1) == 4
        mo_acc(tl(nodes), tl(spec), i + 1, if (eats) { [{elem(n, 0), elem(n, 1), elem(sp, 0) + (if (i == 0) { 0.006 } else { 0.014 })} | acc] } else { acc })
    }
}
fun touches(pts, x, y) {
    if (length(pts) == 0) { false }
    else { q = hd(pts)  dx = x - elem(q, 0)  dy = y - elem(q, 1)  if (dx * dx + dy * dy < elem(q, 2) * elem(q, 2)) { true } else { touches(tl(pts), x, y) } }
}

# ------------------------------------------------------------
# World: plants grow in drifting patches, corpses become meat, two predators
# ------------------------------------------------------------
# every island has its own map
#   0 Green Meadows   a rock reef in one corner, three small vents, a ring of six meadows
#   1 Toxic Marsh     six big vents, a few rocks, four meadows squeezed between the vents
#   2 Lean Waters     a maze of twelve boulders, one vent, three small meadows far apart
#   3 Rich Shallows   open water, one tiny vent, eight meadows close together
# eight environments; island i lives in environment i % 8
#   0 Green Meadows  1 Toxic Marsh  2 Lean Waters  3 Rich Shallows      (the evolved four)
#   4 Coral Reef     5 Kelp Forest  6 Arctic Ice   7 Black Smoker       (new, fresh evolution)
# force_env >= 0 puts every island in that environment (one big world split into islands)
let force_env = 0 - 1
fun env(i) { if (force_env >= 0) { force_env } else { nth([0, 6, 5, 4, 7, 1, 2, 3], i % 8) } }
fun obstacles(i) { obst_c(env(i)) }
fun obst_c(i) {
    if (i == 0) { [[1.20, 1.18, 0.07], [1.33, 1.28, 0.06], [1.17, 1.36, 0.05], [1.40, 1.12, 0.045], [1.29, 1.44, 0.045], [0.40, 0.45, 0.06], [1.10, 0.38, 0.05], [0.30, 1.30, 0.05]] }
    else { if (i == 1) { [[0.80, 0.22, 0.05], [1.45, 0.80, 0.05], [0.15, 0.80, 0.05]] }
    else { if (i == 2) { [[0.30, 0.30, 0.08], [0.80, 0.22, 0.07], [1.30, 0.30, 0.08], [0.22, 0.80, 0.07], [1.38, 0.80, 0.07], [0.30, 1.30, 0.08],
                         [0.80, 1.38, 0.07], [1.30, 1.30, 0.08], [0.55, 0.55, 0.06], [1.05, 0.55, 0.06], [0.55, 1.05, 0.06], [1.05, 1.05, 0.06]] }
    else { if (i == 3) { [[0.25, 1.35, 0.05], [1.35, 0.25, 0.05]] }
    else { if (i == 4) { [[0.450, 0.450, 0.055], [0.525, 0.450, 0.032], [0.473, 0.521, 0.032], [0.389, 0.494, 0.032], [0.389, 0.406, 0.032], [0.473, 0.379, 0.032], [1.150, 0.420, 0.055], [1.207, 0.468, 0.032], [1.122, 0.489, 0.032], [1.075, 0.415, 0.032], [1.132, 0.347, 0.032], [1.214, 0.380, 0.032], [0.800, 0.880, 0.055], [0.813, 0.954, 0.032], [0.734, 0.915, 0.032], [0.746, 0.828, 0.032], [0.833, 0.813, 0.032], [0.874, 0.891, 0.032], [0.400, 1.220, 0.055], [0.362, 1.285, 0.032], [0.327, 1.204, 0.032], [0.393, 1.145, 0.032], [0.469, 1.190, 0.032], [0.450, 1.276, 0.032], [1.220, 1.200, 0.055], [1.149, 1.225, 0.032], [1.174, 1.141, 0.032], [1.262, 1.138, 0.032], [1.292, 1.221, 0.032], [1.222, 1.275, 0.032]] }
    else { if (i == 5) { [[0.25, 0.30, 0.05], [1.35, 1.40, 0.06], [1.45, 0.25, 0.04]] }
    else { if (i == 6) { [[0.400, 0.400, 0.120], [1.150, 0.350, 0.100], [0.750, 0.900, 0.140], [0.300, 1.250, 0.090], [1.250, 1.200, 0.110], [0.950, 1.450, 0.060], [0.400, 0.530, 0.070], [1.250, 0.400, 0.060]] }
    else { [[0.55, 1.30, 0.06], [1.30, 0.45, 0.05], [1.40, 1.45, 0.05], [0.20, 0.90, 0.045]] } } } } } } }
}

# toxic vents: standing in one burns health
fun vents(i) { vents_c(env(i)) }
fun vents_c(i) {
    if (i == 0) { [[0.80, 0.80, 0.12], [1.36, 0.26, 0.10], [0.20, 0.62, 0.09]] }
    else { if (i == 1) { [[0.40, 0.40, 0.13], [1.20, 0.38, 0.12], [0.80, 0.80, 0.14], [0.38, 1.20, 0.12], [1.22, 1.22, 0.13], [0.80, 1.47, 0.08]] }
    else { if (i == 2) { [[0.80, 0.80, 0.07]] }
    else { if (i == 3) { [[1.42, 1.42, 0.05]] }
    else { if (i == 4) { [[1.42, 0.80, 0.07]] }
    else { if (i == 5) { [[1.45, 0.75, 0.06]] }
    else { if (i == 6) { [[1.45, 0.80, 0.05]] }
    else { [[0.800, 0.800, 0.100], [0.350, 0.350, 0.060], [1.250, 1.200, 0.070]] } } } } } } }
}

# kelp beds: inside one you are hidden from others (unless very close) but you swim slower
fun kelp(i) { if (env(i) == 5) { [[0.500, 0.500, 0.170], [1.100, 0.500, 0.150], [0.800, 1.050, 0.180], [0.350, 1.250, 0.120], [1.300, 1.100, 0.130]] } else { [] } }
fun in_zone(x, y, lst) {
    if (length(lst) == 0) { false }
    else { z = hd(lst)  dx = x - hd(z)  dy = y - nth(z, 1)  if (dx * dx + dy * dy < nth(z, 2) * nth(z, 2)) { true } else { in_zone(x, y, tl(lst)) } }
}
# near coral: within 0.03 of a coral head's edge
fun near_coral(x, y, lst) {
    if (length(lst) == 0) { false }
    else { z = hd(lst)  dx = x - hd(z)  dy = y - nth(z, 1)  r = nth(z, 2) + 0.03  if (dx * dx + dy * dy < r * r) { true } else { near_coral(x, y, tl(lst)) } }
}
# food grows around fixed centres in the new environments
fun food_centres(e) {
    if (e == 4) { [[0.450, 0.450, 0.000], [1.150, 0.420, 0.000], [0.800, 0.880, 0.000], [0.400, 1.220, 0.000], [1.220, 1.200, 0.000]] }
    else { if (e == 5) { [[0.500, 0.500, 0.170], [1.100, 0.500, 0.150], [0.800, 1.050, 0.180], [0.350, 1.250, 0.120], [1.300, 1.100, 0.130]] }
    else { if (e == 6) { [[0.400, 0.400, 0.120], [1.150, 0.350, 0.100], [0.750, 0.900, 0.140], [0.300, 1.250, 0.090], [1.250, 1.200, 0.110], [0.950, 1.450, 0.060]] }
    else { [] } } }
}

fun meadow_count(i) { nth([6, 4, 3, 8, 5, 5, 6, 3], env(i)) }
fun meadow_ring(i) { nth([0.31, 0.27, 0.38, 0.24, 0.3, 0.3, 0.3, 0.3], env(i)) }

fun toxicity(x, y, lst) {
    if (length(lst) == 0) { 0.0 }
    else {
        v = hd(lst)
        dx = x - hd(v)
        dy = y - nth(v, 1)
        d = Math.sqrt(dx * dx + dy * dy)
        fmax(if (d < nth(v, 2)) { 1.0 - d / nth(v, 2) * 0.6 } else { 0.0 }, toxicity(x, y, tl(lst)))
    }
}

fun in_obstacle(x, y, obs) {
    if (length(obs) == 0) { false }
    else {
        o = hd(obs)
        dx = x - hd(o)
        dy = y - nth(o, 1)
        r = nth(o, 2) + 0.02
        if (dx * dx + dy * dy < r * r) { true } else { in_obstacle(x, y, tl(obs)) }
    }
}

fun clampw(v) { clampf(v, 0.02, WS - 0.02) }

fun patch_center(i, k, t) {
    fc = food_centres(env(i))
    if (length(fc) > 0) { c = nth(fc, k % length(fc))  {hd(c), nth(c, 1)} } else { ring_center(i, k, t) }
}
fun ring_center(i, k, t) {
    a = to_float(k) * 6.2832 / to_float(meadow_count(i)) + to_float(t) * 0.00002
    {0.5 * WS + meadow_ring(i) * WS * Math.cos(a), 0.5 * WS + meadow_ring(i) * WS * Math.sin(a)}
}

# half the algae grows anywhere, half in wide drifting patches: spinning on the spot does not pay
fun plant_pos(i, t, tries) { if (env(i) == 7) { smoker_food(i, tries) } else { plant_pos2(i, t, tries) } }
# around a black smoker: a ring of bacterial mats just outside the deadly mouth
fun smoker_food(i, tries) {
    v = nth(vents(i), rndi(length(vents(i))))
    a = rndf() * 6.2832
    d = nth(v, 2) + 0.025 + rndf() * 0.13
    x = clampw(hd(v) + Math.cos(a) * d)
    y = clampw(nth(v, 1) + Math.sin(a) * d)
    if (tries <= 0 || (in_obstacle(x, y, obstacles(i)) == false && toxicity(x, y, vents(i)) == 0.0)) { [x, y, 0] } else { smoker_food(i, tries - 1) }
}
fun plant_pos2(i, t, tries) {
    c = patch_center(i, rndi(meadow_count(i)), t)
    anywhere = rndf() < (if (env(i) >= 4) { 0.15 } else { 0.35 })
    x = if (anywhere) { 0.04 + rndf() * (WS - 0.08) } else { clampw(elem(c, 0) + gauss() * 0.15) }
    y = if (anywhere) { 0.04 + rndf() * (WS - 0.08) } else { clampw(elem(c, 1) + gauss() * 0.15) }
    # no food grows inside a vent: food there would reward swimming into the danger the vent punishes
    if (tries <= 0 || (in_obstacle(x, y, obstacles(i)) == false && toxicity(x, y, vents(i)) == 0.0)) { [x, y, 0] } else { plant_pos2(i, t, tries - 1) }
}

fun init_plants(i, k, t) { ip_acc(i, k, t, []) }
fun ip_acc(i, k, t, acc) { if (k <= 0) { acc } else { ip_acc(i, k - 1, t, [plant_pos(i, t, 10) | acc]) } }

fun free_pos(i, tries) {
    x = 0.06 + rndf() * (WS - 0.12)
    y = 0.06 + rndf() * (WS - 0.12)
    if (tries <= 0 || (in_obstacle(x, y, obstacles(i)) == false && toxicity(x, y, vents(i)) == 0.0)) { [x, y] } else { free_pos(i, tries - 1) }
}

# poison algae: mostly around the vents, some anywhere
fun poison_pos(i) {
    v = nth(vents(i), rndi(length(vents(i))))
    if (rndf() < 0.7) { [clampw(hd(v) + gauss() * nth(v, 2) * 1.6), clampw(nth(v, 1) + gauss() * nth(v, 2) * 1.6)] }
    else { [0.04 + rndf() * (WS - 0.08), 0.04 + rndf() * (WS - 0.08)] }
}
fun init_poison(i, k) { ipo_acc(i, k, []) }
fun ipo_acc(i, k, acc) { if (k <= 0) { acc } else { ipo_acc(i, k - 1, [poison_pos(i) | acc]) } }

fun slots(k, hi) { rev(slots_acc(k, hi, []), []) }
fun slots_acc(k, hi, acc) { if (k >= hi) { acc } else { slots_acc(k + 1, hi, [k | acc]) } }

# four islands, four climates: same rocks and vents, different food, poison and vent strength
fun isl_plants(i) { nth([120, 120, 80, 160, 130, 120, 95, 120], env(i)) }
fun isl_poison(i) { nth([30, 75, 20, 30, 20, 15, 10, 35], env(i)) }
fun isl_vk(i) { nth([1.0, 2.2, 1.0, 1.0, 1.5, 1.0, 1.0, 3.0], env(i)) }
fun nisl(tab) { num(cget(tab, 'n_isl')) }

fun new_world(isl) {
    %{crs: [], plants: init_plants(isl, isl_plants(isl), 0), meat: [], poison: init_poison(isl, isl_poison(isl)),
      preds: [], isl: isl, vk: isl_vk(isl), cap: isl_cap, sptree: [], mig_in: 0, mig_out: 0,
      free: slots(isl * max_slots, (isl + 1) * max_slots), next_id: isl * 10000000 + 1, tick: 0, init: 0,
      b_sex: 0, b_bud: 0, b_imm: 0, d_starve: 0, d_pred: 0, d_eaten: 0, d_old: 0, d_toxic: 0,
      maxgen: 0, sps: [], sp_next: isl * 100000 + 1, hof: [], evs: [], ck_tick: 0, ck_note: "", pred_on: 1, hist: []}
}

# ---- senses: 18 numbers per creature ----
#  0 bias  1 plant angle 2 plant near  3 meat angle 4 meat near
#  5 creature angle 6 near 7 kinship 8 relative size 9 its signal
#  10 predator angle 11 near 12 threat  13 wall ahead  14 energy 15 health 16 pain 17 heard signal
fun rel(hx, hy, dx, dy, d) {
    dd = d + 0.000001
    dot = (hx * dx + hy * dy) / dd
    cross = (hx * dy - hy * dx) / dd
    if (dot >= 0.0) { cross } else { if (cross >= 0.0) { 1.0 } else { 0.0 - 1.0 } }
}

fun nearest_item(lst, x, y, best) {
    if (length(lst) == 0) { best }
    else {
        it = hd(lst)
        dx = hd(it) - x
        dy = nth(it, 1) - y
        d = Math.sqrt(dx * dx + dy * dy)
        ok = nth(it, 2) <= 0 && (best == nil || d < hd(best))
        nearest_item(tl(lst), x, y, if (ok) { [d, dx, dy] } else { best })
    }
}

fun nearest_meat(lst, x, y, best) {
    if (length(lst) == 0) { best }
    else {
        it = hd(lst)
        dx = hd(it) - x
        dy = nth(it, 1) - y
        d = Math.sqrt(dx * dx + dy * dy)
        nearest_meat(tl(lst), x, y, if (best == nil || d < hd(best)) { [d, dx, dy] } else { best })
    }
}

# one pass over the other creatures: nearest one, and the mean signal heard nearby
# a compact tuple per creature, built once per tick, so the pairwise scans read tuple fields
# instead of looking keys up in each creature's map
fun cellc(v) { k = to_int(v / 0.2)  if (k < 0) { 0 } else { if (k > 7) { 7 } else { k } } }
fun gbuild(lst, m) {
    if (length(lst) == 0) { m }
    else { t = hd(lst)  k = cellc(elem(t, 1)) * 8 + cellc(elem(t, 0))  gbuild(tl(lst), map_put(m, k, [t | list_or_empty(map_get(m, k))])) }
}
fun ring(r) { if (r == 0) { [{0, 0}] } else { ring_acc(r, 0 - r, []) } }
fun ring_acc(r, dx, acc) {
    if (dx > r) { acc }
    else { ring_acc(r, dx + 1, if (dx == 0 - r || dx == r) { col_all(dx, 0 - r, r, acc) } else { [{dx, 0 - r}, {dx, r} | acc] }) }
}
fun col_all(dx, dy, r, acc) { if (dy > r) { acc } else { col_all(dx, dy + 1, r, [{dx, dy} | acc]) } }
# nearest item passing okf, searching outwards ring by ring; stops once nothing closer can exist or beyond maxd
fun ng(grid, cx, cy, x, y, r, maxd, best, okf) {
    lim = to_float(r - 1) * 0.2
    if (r > 8 || lim > maxd || (best != nil && Math.sqrt(elem(best, 0)) <= lim)) { best }
    else { ng(grid, cx, cy, x, y, r + 1, maxd, ng_cells(grid, ring(r), cx, cy, x, y, best, okf), okf) }
}
fun ng_cells(grid, offs, cx, cy, x, y, best, okf) {
    if (length(offs) == 0) { best }
    else {
        o = hd(offs)
        gx = cx + elem(o, 0)
        gy = cy + elem(o, 1)
        b2 = if (gx < 0 || gy < 0 || gx > 7 || gy > 7) { best } else { ng_items(list_or_empty(map_get(grid, gy * 8 + gx)), x, y, best, okf) }
        ng_cells(grid, tl(offs), cx, cy, x, y, b2, okf)
    }
}
fun ng_items(lst, x, y, best, okf) {
    if (length(lst) == 0) { best }
    else {
        t = hd(lst)
        dx = elem(t, 0) - x
        dy = elem(t, 1) - y
        d2 = dx * dx + dy * dy
        ng_items(tl(lst), x, y, if ((best == nil || d2 < elem(best, 0)) && okf(t, d2)) { {d2, dx, dy, t} } else { best }, okf)
    }
}
# mean signal of others within 0.15 (cells of rings 0 and 1)
fun sig_near(grid, cx, cy, x, y, id) {
    r = sig_cells(grid, app(ring(0), ring(1)), cx, cy, x, y, id, 0.0, 0)
    if (elem(r, 1) > 0) { elem(r, 0) / to_float(elem(r, 1)) } else { 0.0 }
}
fun sig_cells(grid, offs, cx, cy, x, y, id, sum, cnt) {
    if (length(offs) == 0) { {sum, cnt} }
    else {
        o = hd(offs)
        gx = cx + elem(o, 0)
        gy = cy + elem(o, 1)
        r = if (gx < 0 || gy < 0 || gx > 7 || gy > 7) { {sum, cnt} } else { sig_items(list_or_empty(map_get(grid, gy * 8 + gx)), x, y, id, sum, cnt) }
        sig_cells(grid, tl(offs), cx, cy, x, y, id, elem(r, 0), elem(r, 1))
    }
}
fun sig_items(lst, x, y, id, sum, cnt) {
    if (length(lst) == 0) { {sum, cnt} }
    else {
        t = hd(lst)
        dx = elem(t, 0) - x
        dy = elem(t, 1) - y
        near = elem(t, 2) != id && dx * dx + dy * dy < 0.0225
        sig_items(tl(lst), x, y, id, if (near) { sum + elem(t, 5) } else { sum }, if (near) { cnt + 1 } else { cnt })
    }
}
fun plant_tuples(lst, acc) { if (length(lst) == 0) { acc } else { it = hd(lst)  plant_tuples(tl(lst), if (nth(it, 2) > 0) { acc } else { [{hd(it), nth(it, 1)} | acc] }) } }

fun mk_oth(crs, acc) {
    if (length(crs) == 0) { acc }
    else { c = hd(crs)  mk_oth(tl(crs), [{g(c, 'x'), g(c, 'y'), g(c, 'id'), g(c, 'sp'), power(c), g(c, 'sig'), g(c, 'bite'), g(c, 'ph'), in_zone(g(c, 'x'), g(c, 'y'), kelp(g(c, 'isl')))} | acc]) }
}

fun scan_oth(lst, x, y, id, best, sig, cnt) {
    if (length(lst) == 0) { {best, if (cnt > 0) { sig / to_float(cnt) } else { 0.0 }} }
    else {
        o = hd(lst)
        if (elem(o, 2) == id) { scan_oth(tl(lst), x, y, id, best, sig, cnt) }
        else {
            dx = elem(o, 0) - x
            dy = elem(o, 1) - y
            d2 = dx * dx + dy * dy
            hidden = elem(o, 8) && d2 > 0.0036
            near = d2 < 0.0225
            nb = if (hidden == false && (best == nil || d2 < elem(best, 0))) { {d2, dx, dy, o} } else { best }
            scan_oth(tl(lst), x, y, id, nb, if (near) { sig + elem(o, 5) } else { sig }, if (near) { cnt + 1 } else { cnt })
        }
    }
}

fun hunter_oth(lst, x, y, id, sp, mine, best) {
    if (length(lst) == 0) { best }
    else {
        o = hd(lst)
        ok = elem(o, 2) != id && elem(o, 3) != sp && elem(o, 4) > mine && hd(tl(tl(tl(elem(o, 7))))) >= 0.8
        if (ok) {
            dx = elem(o, 0) - x
            dy = elem(o, 1) - y
            d2 = dx * dx + dy * dy
            seen = elem(o, 8) == false || d2 < 0.0036
            hunter_oth(tl(lst), x, y, id, sp, mine, if (seen && (best == nil || d2 < elem(best, 0))) { {d2, dx, dy, o} } else { best })
        } else { hunter_oth(tl(lst), x, y, id, sp, mine, best) }
    }
}

# {d2, dx, dy, o} -> [d, dx, dy, o]
fun unsq(b) { if (b == nil) { nil } else { [Math.sqrt(elem(b, 0)), elem(b, 1), elem(b, 2), elem(b, 3)] } }

fun scan_crs(crs, c, best, sig, cnt) {
    if (length(crs) == 0) { {best, if (cnt > 0) { sig / to_float(cnt) } else { 0.0 }} }
    else {
        o = hd(crs)
        if (g(o, 'id') == g(c, 'id')) { scan_crs(tl(crs), c, best, sig, cnt) }
        else {
            dx = g(o, 'x') - g(c, 'x')
            dy = g(o, 'y') - g(c, 'y')
            d = Math.sqrt(dx * dx + dy * dy)
            near = d < 0.15
            scan_crs(tl(crs), c, if (best == nil || d < hd(best)) { [d, dx, dy, o] } else { best },
                     if (near) { sig + g(o, 'sig') } else { sig }, if (near) { cnt + 1 } else { cnt })
        }
    }
}

# the predators are creatures too: a "hunter" is any stranger that is stronger than me (attack x size)
fun power(c) { numf(g(c, 'pw')) }
fun nearest_hunter(crs, c, mine, best) {
    if (length(crs) == 0) { best }
    else {
        o = hd(crs)
        dx = g(o, 'x') - g(c, 'x')
        dy = g(o, 'y') - g(c, 'y')
        d = Math.sqrt(dx * dx + dy * dy)
        ok = g(o, 'id') != g(c, 'id') && g(o, 'sp') != g(c, 'sp') && power(o) > mine && nth(g(o, 'ph'), 3) >= 0.8
        nearest_hunter(tl(crs), c, mine, if (ok && (best == nil || d < hd(best))) { [d, dx, dy, o] } else { best })
    }
}

fun nearest_pred(lst, x, y, best) {
    if (length(lst) == 0) { best }
    else {
        pr = hd(lst)
        dx = hd(pr) - x
        dy = nth(pr, 1) - y
        d = Math.sqrt(dx * dx + dy * dy)
        nearest_pred(tl(lst), x, y, if (best == nil || d < hd(best)) { [d, dx, dy, nth(pr, 2)] } else { best })
    }
}

fun wall_t(x, y, dx, dy) {
    tx = if (dx > 0.0) { (WS - x) / dx } else { if (dx < 0.0) { (0.0 - x) / dx } else { 99.0 } }
    ty = if (dy > 0.0) { (WS - y) / dy } else { if (dy < 0.0) { (0.0 - y) / dy } else { 99.0 } }
    fmin(tx, ty)
}

fun nearest_poison(lst, x, y, best) {
    if (length(lst) == 0) { best }
    else {
        it = hd(lst)
        dx = hd(it) - x
        dy = nth(it, 1) - y
        d = Math.sqrt(dx * dx + dy * dy)
        nearest_poison(tl(lst), x, y, if (best == nil || d < hd(best)) { [d, dx, dy] } else { best })
    }
}

fun see(item, sight, hx, hy) {
    if (item == nil || hd(item) > sight) { [0.0, 0.0] }
    else { [rel(hx, hy, nth(item, 1), nth(item, 2), hd(item)), 1.0 - hd(item) / sight] }
}

fun senses(s, c) {
    x = g(c, 'x')
    y = g(c, 'y')
    hx = g(c, 'hx')
    hy = g(c, 'hy')
    ph = g(c, 'ph')
    sight = g(c, 'sight') * (if (env(g(c, 'isl')) == 7) { 0.6 } else { 1.0 })
    cg = g(s, 'cg')
    cx = cellc(x)
    cy = cellc(y)
    id = g(c, 'id')
    spc = g(c, 'sp')
    mine = power(c)
    pl = see(unsq(ng(g(s, 'pg'), cx, cy, x, y, 0, sight, nil, fun(t, d2) { true })), sight, hx, hy)
    mt = see(nearest_meat(g(s, 'meat'), x, y, nil), sight, hx, hy)
    nb = unsq(ng(cg, cx, cy, x, y, 0, sight, nil, fun(t, d2) { elem(t, 2) != id && (elem(t, 8) == false || d2 < 0.0036) }))
    heard = sig_near(cg, cx, cy, x, y, id)
    cv = see(nb, sight, hx, hy)
    seen = nb != nil && hd(nb) <= sight
    o = if (nb == nil) { nil } else { nth(nb, 3) }
    kin = if (seen) { fmax(0.0, 1.0 - body_dist(ph, elem(o, 7), 0) / 2.5) } else { 0.0 }
    sz = if (seen) { hd(elem(o, 7)) - hd(ph) } else { 0.0 }
    osig = if (seen) { elem(o, 5) } else { 0.0 }
    # the "stronger stranger" search usually finds nothing and widens over the whole island,
    # so it refreshes every 4th tick per creature (staggered) and reuses the last reading in between
    old = g(c, 'sv')
    fresh_h = old == nil || length(old) < n_sens || (g(s, 'tick') + id) % 4 == 0
    hn = if (fresh_h) { unsq(ng(cg, cx, cy, x, y, 0, sight * 1.3, nil, fun(t, d2) { elem(t, 2) != id && elem(t, 3) != spc && elem(t, 4) > mine && elem(t, 4) >= 0.5 && (elem(t, 8) == false || d2 < 0.0036) })) } else { nil }
    po = see(nearest_poison(g(s, 'poison'), x, y, nil), sight, hx, hy)
    pv = if (fresh_h) { see(hn, sight * 1.3, hx, hy) } else { [nth(old, 10), nth(old, 11)] }
    threat = if (fresh_h == false) { nth(old, 12) } else { if (hn == nil || hd(hn) > sight * 1.3) { 0.0 } else { if (elem(nth(hn, 3), 6) == 1) { 1.0 } else { 0.5 } } }
    wa = 1.0 - fmin(wall_t(x, y, hx, hy), 0.25) / 0.25
    [1.0, hd(pl), nth(pl, 1), hd(mt), nth(mt, 1), hd(cv), nth(cv, 1), kin, sz, osig,
     hd(pv), nth(pv, 1), threat, wa, g(c, 'e') / 100.0, g(c, 'h') / 100.0, if (g(c, 'pain') > 0) { 1.0 } else { 0.0 }, heard,
     hd(po), nth(po, 1), toxicity(x, y, vents(g(c, 'isl'))), toxicity(x + hx * 0.09, y + hy * 0.09, vents(g(c, 'isl'))),
     if (num(g(c, 'ate')) > 0) { 1.0 } else { 0.0 }]
}

# ------------------------------------------------------------
# The tick
# ------------------------------------------------------------
# senses are recomputed every other tick (staggered across creatures); in between only the
# body senses (energy, health, pain) are refreshed
fun live_body(sv, c) { set_at(set_at(set_at(sv, 14, g(c, 'e') / 100.0), 15, g(c, 'h') / 100.0), 16, if (g(c, 'pain') > 0) { 1.0 } else { 0.0 }) }

# ---- parallel senses: each tick the island splits its creatures into chunks and spawns a short-lived
# worker process per chunk. A worker gets a slim view of the world, computes senses, sends each
# creature's neurons their tick, and returns the senses to the island.
fun slim(c) {
    %{id: g(c, 'id'), x: g(c, 'x'), y: g(c, 'y'), hx: g(c, 'hx'), hy: g(c, 'hy'), ph: g(c, 'ph'), sp: g(c, 'sp'), isl: g(c, 'isl'),
      e: g(c, 'e'), h: g(c, 'h'), pain: g(c, 'pain'), sv: g(c, 'sv'), pids: g(c, 'pids'), sight: g(c, 'sight'), pw: g(c, 'pw'), ate: g(c, 'ate')}
}
fun chunks(crs, k, cur, n, acc) {
    if (length(crs) == 0) { if (length(cur) == 0) { acc } else { [cur | acc] } }
    else { if (n >= k) { chunks(crs, k, [], 0, [cur | acc]) } else { chunks(tl(crs), k, [slim(hd(crs)) | cur], n + 1, acc) } }
}
fun spawn_workers(world, view, lst, plast, n) {
    if (length(lst) == 0) { n }
    else { ch = hd(lst)  spawn(sense_worker(world, view, ch, plast))  spawn_workers(world, view, tl(lst), plast, n + 1) }
}
fun sense_worker(world, view, ch, plast) { send(world, {'sv', sw_chunk(view, ch, plast, [])}) }
fun sw_chunk(view, ch, plast, acc) {
    if (length(ch) == 0) { acc }
    else {
        c = hd(ch)
        old = g(c, 'sv')
        sv = if ((g(view, 'tick') + g(c, 'id')) % 2 == 1 && old != nil && length(old) == n_sens) { live_body(old, c) } else { senses(view, c) }
        send_all(g(c, 'pids'), {'tick', sv, plast})
        sw_chunk(view, tl(ch), plast, [{g(c, 'id'), sv} | acc])
    }
}
fun collect_sv(k, m) {
    if (k <= 0) { m }
    else {
        receive {
            {'sv', lst} -> collect_sv(k - 1, put_svs(lst, m))
            after 2000 { m }
        }
    }
}
fun put_svs(lst, m) { if (length(lst) == 0) { m } else { r = hd(lst)  put_svs(tl(lst), map_put(m, elem(r, 0), elem(r, 1))) } }
fun apply_svs(crs, m, acc) { if (length(crs) == 0) { acc } else { c = hd(crs)  sv = map_get(m, g(c, 'id'))  apply_svs(tl(crs), m, [if (sv == nil) { c } else { p(c, 'sv', sv) } | acc]) } }
fun sense_par(world, s, crs, plast) {
    view = %{cg: g(s, 'cg'), pg: g(s, 'pg'), meat: g(s, 'meat'), poison: g(s, 'poison'), tick: g(s, 'tick')}
    per = if (length(crs) > 96) { 24 } else { 32 }
    k = spawn_workers(world, view, chunks(crs, per, [], 0, []), plast, 0)
    apply_svs(crs, collect_sv(k, %{}), [])
}

fun sense_all(s, crs, plast, acc) {
    if (length(crs) == 0) { acc }
    else {
        c = hd(crs)
        old = g(c, 'sv')
        sv = if ((g(s, 'tick') + g(c, 'id')) % 2 == 1 && old != nil && length(old) == n_sens) { live_body(old, c) } else { senses(s, c) }
        send_all(g(c, 'pids'), {'tick', sv, plast})
        sense_all(s, tl(crs), plast, [p(c, 'sv', sv) | acc])
    }
}

fun count_neurons(crs, acc) { if (length(crs) == 0) { acc } else { count_neurons(tl(crs), acc + g(hd(crs), 'nn')) } }
fun count_conns(crs, acc) { if (length(crs) == 0) { acc } else { count_conns(tl(crs), acc + g(hd(crs), 'nc')) } }

fun wait_acks(n, deadline) {
    if (n <= 0) { 0 }
    else {
        receive {
            {'a'} -> wait_acks(n - 1, deadline)
            after 40 { n }
        }
    }
}

fun drain_acks() {
    receive {
        {'a'} -> drain_acks()
        after 0 { 'ok' }
    }
}

fun read_acts(tab, slot, k, n) { if (k >= n) { [] } else { [numf(tget(tab, k_act + slot * nmax + k)) | read_acts(tab, slot, k + 1, n)] } }
fun numf(x) { if (x == nil) { 0.0 } else { x } }

fun rotate_h(hx, hy, ang) {
    c = Math.cos(ang)
    sn = Math.sin(ang)
    nx = hx * c - hy * sn
    ny = hx * sn + hy * c
    len = Math.sqrt(nx * nx + ny * ny) + 0.000001
    {nx / len, ny / len}
}

fun push_out(x, y, obs) {
    if (length(obs) == 0) { {x, y} }
    else {
        o = hd(obs)
        dx = x - hd(o)
        dy = y - nth(o, 1)
        r = nth(o, 2) + 0.015
        d2 = dx * dx + dy * dy
        if (d2 < r * r) { d = Math.sqrt(d2) + 0.000001  {hd(o) + dx / d * r, nth(o, 1) + dy / d * r} } else { push_out(x, y, tl(obs)) }
    }
}

# outputs: 0 turn, 1 thrust, 2 bite, 3 signal, 4 mate
fun act_one(tab, c) {
    o = read_acts(tab, g(c, 'slot'), 0, n_out)
    thrust = fmax(0.0, nth(o, 1))
    slowk = if (in_zone(g(c, 'x'), g(c, 'y'), kelp(g(c, 'isl')))) { 1.8 } else { 1.0 }
    bhx = if (g(c, 'bhx') == nil) { g(c, 'hx') } else { g(c, 'bhx') }
    bhy = if (g(c, 'bhy') == nil) { g(c, 'hy') } else { g(c, 'bhy') }
    tf = 0.75 * numf(g(c, 'tf')) + 0.25 * hd(o)
    r = physics(g(c, 'spec'), g(c, 'nodes'), bhx, bhy, numf(g(c, 'om')), g(c, 'ph'), thrust, tf, g(c, 'age') + g(c, 'id'), slowk, obstacles(g(c, 'isl')), numf(g(c, 'mass')))
    shx0 = 0.8 * g(c, 'hx') + 0.2 * elem(r, 1)
    shy0 = 0.8 * g(c, 'hy') + 0.2 * elem(r, 2)
    shl = Math.sqrt(shx0 * shx0 + shy0 * shy0) + 0.000001
    nodes = elem(r, 0)
    core = hd(nodes)
    c1 = p(p(p(p(p(p(p(p(p(c, 'nodes', nodes), 'x', elem(core, 0)), 'y', elem(core, 1)), 'bhx', elem(r, 1)), 'bhy', elem(r, 2)), 'hx', shx0 / shl), 'hy', shy0 / shl), 'om', elem(r, 4)), 'tf', tf)
    p(p(p(p(p(c1, 'e', g(c1, 'e') - elem(r, 3)), 'outs', o), 'sig', nth(o, 3)), 'bite', if (nth(o, 2) > 0.3) { 1 } else { 0 }), 'mate', if (nth(o, 4) > 0.0) { 1 } else { 0 })
}

fun flee_pass(tab, isl, all, crs) {
    if (length(crs) == 0) { 'ok' }
    else {
        c = hd(crs)
        id = g(c, 'id')
        spc = g(c, 'sp')
        mine = power(c)
        hn = unsq(ng(all, cellc(g(c, 'x')), cellc(g(c, 'y')), g(c, 'x'), g(c, 'y'), 0, g(c, 'sight') * 1.3, nil, fun(t, d2) { elem(t, 2) != id && elem(t, 3) != spc && elem(t, 4) > mine && elem(t, 4) >= 0.5 && (elem(t, 8) == false || d2 < 0.0036) }))
        sight = nth(g(c, 'ph'), 4) * 1.3
        if (hn != nil && hd(hn) < sight && hd(hn) > 0.0001) {
            vmax = 0.011 * nth(g(c, 'ph'), 1) + 0.000001
            f = clampf(numf(g(c, 'v')) / vmax, 0.0, 1.0) * (0.0 - (g(c, 'hx') * nth(hn, 1) + g(c, 'hy') * nth(hn, 2)) / hd(hn))
            cput(tab, k_isl + 500 + isl * 2, numf(cget(tab, k_isl + 500 + isl * 2)) + f)
            cput(tab, k_isl + 501 + isl * 2, num(cget(tab, k_isl + 501 + isl * 2)) + 1)
        } else { 'x' }
        flee_pass(tab, isl, all, tl(crs))
    }
}

fun act_all(tab, crs, acc) { if (length(crs) == 0) { acc } else { act_all(tab, tl(crs), [act_one(tab, hd(crs)) | acc]) } }

# ---- eating ----
fun eat_plants(lst, c, t, acc, ate) {
    if (length(lst) == 0) { {acc, ate} }
    else {
        it = hd(lst)
        tm = nth(it, 2)
        if (tm > 0) { eat_plants(tl(lst), c, t, [it | acc], ate) }
        else {
            if (ate == 0 && touches(g(c, 'mpts'), hd(it), nth(it, 1))) { eat_plants(tl(lst), c, t, [[hd(it), nth(it, 1), 160] | acc], 1) }
            else { eat_plants(tl(lst), c, t, [it | acc], ate) }
        }
    }
}

# eaten plants regrow somewhere in a patch once their timer runs out (once per tick)
fun grow_plants(i, lst, t) { rev(grow_acc(i, lst, t, []), []) }
fun grow_acc(i, lst, t, acc) {
    if (length(lst) == 0) { acc }
    else {
        it = hd(lst)
        tm = nth(it, 2)
        grow_acc(i, tl(lst), t, [if (tm <= 0) { it } else { if (tm == 1) { plant_pos(i, t, 10) } else { [hd(it), nth(it, 1), tm - 1] } } | acc])
    }
}

fun eat_meat(lst, c, acc, got) {
    if (length(lst) == 0) { {acc, got} }
    else {
        it = hd(lst)
        if (got == 0.0 && touches(g(c, 'mpts'), hd(it), nth(it, 1))) { eat_meat(tl(lst), c, acc, nth(it, 2)) }
        else { eat_meat(tl(lst), c, [it | acc], got) }
    }
}

fun eat_poison(lst, c, acc, hit) {
    if (length(lst) == 0) { {acc, hit} }
    else {
        it = hd(lst)
        if (hit == 0 && touches(g(c, 'mpts'), hd(it), nth(it, 1))) { eat_poison(tl(lst), c, [poison_pos(g(c, 'isl')) | acc], 1) }
        else { eat_poison(tl(lst), c, [it | acc], hit) }
    }
}

# plants feed herbivores best, meat feeds carnivores best (the diet gene)
fun feed_all(s, crs, acc) {
    if (length(crs) == 0) { p(s, 'crs', acc) }
    else {
        c = p(hd(crs), 'mpts', mouths(hd(crs)))
        diet = nth(g(c, 'ph'), 5)
        sv = g(c, 'sv')
        sight = g(c, 'sight')
        near_p = sv == nil || length(sv) < n_sens || (1.0 - nth(sv, 2)) * sight < 0.09
        near_m = sv == nil || length(sv) < n_sens || (1.0 - nth(sv, 4)) * sight < 0.09
        near_q = sv == nil || length(sv) < n_sens || (1.0 - nth(sv, 19)) * sight < 0.09
        q = if (near_q) { eat_poison(g(s, 'poison'), c, [], 0) } else { {g(s, 'poison'), 0} }
        f = if (near_p) { eat_plants(g(s, 'plants'), c, g(s, 'tick'), [], 0) } else { {g(s, 'plants'), 0} }
        m = if (near_m) { eat_meat(g(s, 'meat'), c, [], 0.0) } else { {g(s, 'meat'), 0.0} }
        gain = to_float(elem(f, 1)) * 26.0 * (1.0 - 0.75 * diet) + elem(m, 1) * (0.25 + 0.75 * diet)
        c1 = if (gain > 0.0) { p(p(p(c, 'e', fmin(100.0, g(c, 'e') + gain)), 'eaten', g(c, 'eaten') + 1), 'ate', 8) } else { c }
        c2 = if (elem(q, 1) > 0) { p(p(p(p(c1, 'h', g(c1, 'h') - 24.0), 'e', g(c1, 'e') - 4.0), 'pain', 10), 'killer', 0 - 2) } else { c1 }
        feed_all(p(p(p(s, 'plants', elem(f, 0)), 'meat', elem(m, 0)), 'poison', elem(q, 0)), tl(crs), [c2 | acc])
    }
}

# ---- fighting: a creature that bites hurts whoever is in reach; armor helps ----
fun find_id(crs, id) { if (length(crs) == 0) { nil } else { if (g(hd(crs), 'id') == id) { hd(crs) } else { find_id(tl(crs), id) } } }

fun in_reach(crs, a, best) {
    if (length(crs) == 0) { if (best == nil) { nil } else { elem(best, 1) } }
    else {
        c = hd(crs)
        dx = g(c, 'x') - g(a, 'x')
        dy = g(c, 'y') - g(a, 'y')
        d = Math.sqrt(dx * dx + dy * dy)
        ok = g(c, 'id') != g(a, 'id') && g(c, 'sp') != g(a, 'sp') && g(c, 'h') > 0.0 && d < 0.035 + 0.014 * nth(g(a, 'ph'), 0)
        in_reach(tl(crs), a, if (ok && (best == nil || d < elem(best, 0))) { {d, g(c, 'id')} } else { best })
    }
}

fun upd(crs, id, f) {
    if (length(crs) == 0) { [] } else { if (g(hd(crs), 'id') == id) { [f(hd(crs)) | tl(crs)] } else { [hd(crs) | upd(tl(crs), id, f)] } }
}

fun fight_tuples(crs, acc) { if (length(crs) == 0) { acc } else { c = hd(crs)  fight_tuples(tl(crs), [{g(c, 'x'), g(c, 'y'), g(c, 'id'), g(c, 'sp'), g(c, 'h')} | acc]) } }
fun in_reach_g(grid, a) {
    aid = g(a, 'id')
    asp = g(a, 'sp')
    reach = 0.035 + 0.014 * nth(g(a, 'ph'), 0)
    b = ng(grid, cellc(g(a, 'x')), cellc(g(a, 'y')), g(a, 'x'), g(a, 'y'), 0, reach, nil, fun(t, d2) { elem(t, 2) != aid && elem(t, 3) != asp && elem(t, 4) > 0.0 && d2 < reach * reach })
    if (b == nil) { nil } else { elem(elem(b, 3), 2) }
}
fun fight(crs, snap) { fight_g(crs, snap, gbuild(fight_tuples(crs, []), %{})) }
fun fight_g(crs, snap, grid) {
    if (length(snap) == 0) { crs }
    else {
        a = find_id(crs, g(hd(snap), 'id'))
        if (a != nil && g(a, 'bite') == 1 && g(a, 'acd') <= 0 && g(a, 'h') > 0.0) {
            tid = in_reach_g(grid, a)
            aph = g(a, 'ph')
            if (tid == nil) { fight_g(upd(crs, g(a, 'id'), fun(c) { p(p(c, 'acd', 6), 'e', g(c, 'e') - 0.15) }), tl(snap), grid) }
            else {
                t = find_id(crs, tid)
                shelter = if (env(g(t, 'isl')) == 4 && near_coral(g(t, 'x'), g(t, 'y'), obstacles(g(t, 'isl')))) { 0.5 } else { 1.0 }
                dmg = shelter * 6.0 * nth(aph, 3) * nth(aph, 0) / (1.0 + nth(g(t, 'ph'), 2))
                gain = dmg * 0.6 * (0.25 + 0.75 * nth(aph, 5))
                aid = g(a, 'id')
                crs2 = upd(crs, tid, fun(c) { p(p(p(c, 'h', g(c, 'h') - dmg), 'pain', 10), 'killer', aid) })
                dead = g(t, 'h') - dmg <= 0.0
                crs3 = upd(crs2, aid, fun(c) { p(p(p(c, 'e', fmin(100.0, g(c, 'e') + gain - 0.3)), 'acd', 12), 'kills', g(c, 'kills') + (if (dead) { 1 } else { 0 })) })
                fight_g(crs3, tl(snap), grid)
            }
        } else { fight_g(crs, tl(snap), grid) }
    }
}

# ---- predators: stalk (warning), short chase slower than a fast creature, rest ----
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

fun pred_one(s, pr) {
    px = hd(pr)
    py = nth(pr, 1)
    mode = nth(pr, 2)
    tm = nth(pr, 3)
    tg = nearest_creature(g(s, 'crs'), px, py, nil)
    d = if (tg == nil) { 9.0 } else { hd(tg) + 0.000001 }
    dx = if (tg == nil) { 0.0 } else { nth(tg, 2) }
    dy = if (tg == nil) { 0.0 } else { nth(tg, 3) }
    mode2 = if (mode == 0) { if (d < 0.30 && tm <= 0) { 3 } else { 0 } }
            else { if (mode == 3) { if (tm <= 0) { if (d < 0.40) { 1 } else { 0 } } else { 3 } }
            else { if (mode == 1) { if (tm <= 0 || tg == nil || d > 0.45) { 2 } else { 1 } }
            else { if (tm <= 0) { 0 } else { 2 } } } }
    tm2 = if (mode2 != mode) { if (mode2 == 3) { 55 } else { if (mode2 == 1) { 110 } else { if (mode2 == 2) { 120 } else { 40 } } } } else { tm - 1 }
    wh = rotate_h(nth(pr, 4), nth(pr, 5), (rndf() - 0.5) * 0.3)
    face = (mode2 == 1 || mode2 == 3) && tg != nil
    hx = if (face) { dx / d } else { elem(wh, 0) }
    hy = if (face) { dy / d } else { elem(wh, 1) }
    speed = if (mode2 == 1) { 0.0085 } else { if (mode2 == 0) { 0.003 } else { 0.0 } }
    nx = clampw(px + hx * speed)
    ny = clampw(py + hy * speed)
    if (mode2 == 1 && tg != nil && d < 0.045) {
        tid = nth(tg, 1)
        crs2 = upd(g(s, 'crs'), tid, fun(c) { p(p(p(p(p(c, 'h', g(c, 'h') - 70.0 / (1.0 + 0.6 * nth(g(c, 'ph'), 2))), 'pain', 10), 'killer', 0 - 1),
                                                'x', clampw(g(c, 'x') + dx / d * 0.08)), 'y', clampw(g(c, 'y') + dy / d * 0.08)) })
        {p(s, 'crs', crs2), [nx, ny, 2, 120, hx, hy]}
    } else { {s, [nx, ny, mode2, tm2, hx, hy]} }
}

fun preds_step(s, lst, acc) {
    if (length(lst) == 0) { p(s, 'preds', rev(acc, [])) }
    else { r = pred_one(s, hd(lst))  preds_step(elem(r, 0), tl(lst), [elem(r, 1) | acc]) }
}

# ---- metabolism: body, brain size and wiring all cost energy ----
fun vitals(c) {
    ph = g(c, 'ph')
    sz = nth(ph, 0)
    # Bergmann: heat is lost through the surface (perimeter) and kept by the mass, so in the cold
    # fewer, bigger nodes are cheaper; everywhere mass, nodes and eyes cost energy
    cold = if (env(numf(g(c, 'isl'))) == 6) { 0.04 * numf(g(c, 'perim')) / fmax(0.5, numf(g(c, 'mass'))) } else { 0.0 }
    sightc = numf(g(c, 'sight'))
    cost = cold + 0.010 + 0.0025 * numf(g(c, 'mass')) + 0.0016 * to_float(g(c, 'nn')) + 0.0004 * to_float(g(c, 'nc')) +
           0.0015 * to_float(num(g(c, 'nnodes'))) + 0.012 * sightc * sightc + 0.03 * nth(ph, 11)
    tox = toxicity(g(c, 'x'), g(c, 'y'), vents(g(c, 'isl')))
    regen = g(c, 'e') > 40.0 && g(c, 'h') < 100.0 && tox == 0.0
    c0 = if (tox > 0.0) { p(p(p(c, 'h', g(c, 'h') - 1.2 * tox * numf(g(c, 'vk'))), 'pain', 6), 'killer', 0 - 2) } else { c }
    vitals2(c0, cost, regen)
}

fun vitals2(c, cost, regen) {
    p(p(p(p(p(p(p(c, 'e', g(c, 'e') - cost - (if (regen) { 0.02 } else { 0.0 })), 'h', if (regen) { fmin(100.0, g(c, 'h') + 0.05) } else { g(c, 'h') }),
      'age', g(c, 'age') + 1), 'cool', g(c, 'cool') - 1), 'acd', g(c, 'acd') - 1), 'pain', if (g(c, 'pain') > 0) { g(c, 'pain') - 1 } else { 0 }), 'ate', if (num(g(c, 'ate')) > 0) { num(g(c, 'ate')) - 1 } else { 0 })
}

fun map_vitals(crs, acc) { if (length(crs) == 0) { acc } else { map_vitals(tl(crs), [vitals(hd(crs)) | acc]) } }

# ---- death: the brain's processes stop, the body becomes meat ----
fun reap(tab, s, crs, keep) {
    if (length(crs) == 0) { p(s, 'crs', keep) }
    else {
        c = hd(crs)
        starved = g(c, 'e') <= 0.0
        slain = g(c, 'h') <= 0.0
        old = g(c, 'age') >= g(c, 'life')
        if (starved || slain || old) {
            kill_brain(c)
            why0 = 0
            why = if (slain) { if (g(c, 'killer') > 0) { 6 } else { if (g(c, 'killer') == 0 - 2) { 13 } else { 5 } } } else { if (starved) { 4 } else { 8 } }
            key = if (why == 6) { 'd_eaten' } else { if (why == 13) { 'd_toxic' } else { if (why == 5) { 'd_pred' } else { if (why == 4) { 'd_starve' } else { 'd_old' } } } }
            lin_died(tab, c, why, g(s, 'tick'))
            meat = [g(c, 'x'), g(c, 'y'), 14.0 + 26.0 * nth(g(c, 'ph'), 0), 520]
            s1 = p(p(p(p(s, key, g(s, key) + 1), 'free', [g(c, 'slot') | g(s, 'free')]), 'meat', [meat | g(s, 'meat')]),
                   'hof', hof_add(g(s, 'hof'), c))
            reap(tab, p(s1, 'evs', [[why, g(c, 'slot'), Math.round(nth(g(c, 'ph'), 6)), g(c, 'gen'), g(c, 'age'), g(c, 'kids')] | g(s1, 'evs')]), tl(crs), keep)
        } else { reap(tab, s, tl(crs), [c | keep]) }
    }
}

fun age_meat(lst) { rev(am_acc(lst, []), []) }
fun am_acc(lst, acc) {
    if (length(lst) == 0) { acc }
    else { it = hd(lst)  am_acc(tl(lst), if (nth(it, 3) <= 1) { acc } else { [[hd(it), nth(it, 1), nth(it, 2), nth(it, 3) - 1] | acc] }) }
}

# hall of fame: the genomes that left the most children
fun hof_score(c) { to_float(g(c, 'kids')) * 3.0 + to_float(g(c, 'kills')) + to_float(g(c, 'age')) / 600.0 }
fun hof_add(h, c) {
    sc = hof_score(c)
    if (g(c, 'kids') < 1) { h }
    else {
        h2 = hof_ins(h, [sc, g(c, 'ha'), g(c, 'hb'), g(c, 'gen'), g(c, 'sp'), Math.round(nth(g(c, 'ph'), 6))])
        if (length(h2) > 8) { Std.take(h2, 8) } else { h2 }
    }
}
fun hof_ins(h, e) { if (length(h) == 0) { [e] } else { if (hd(e) >= hd(hd(h))) { [e | h] } else { [hd(h) | hof_ins(tl(h), e)] } } }

# ---- birth ----
fun birth(tab, world, s, ha, hb, gen, sp, x, y, e, mom, dad, kind) {
    fr = g(s, 'free')
    if (length(fr) == 0 || length(g(s, 'crs')) >= g(s, 'cap') || num(cget(tab, 'procs')) > 88000) { s }
    else {
        c = make_creature(tab, world, s, ha, hb, hd(fr), gen, sp, x, y, e, mom, dad)
        lin_put(tab, c, s, kind)
        key = if (kind == 1) { 'b_sex' } else { if (kind == 2) { 'b_bud' } else { if (kind == 4) { 'mig_in' } else { 'b_imm' } } }
        s0 = p(p(p(s, 'crs', [c | g(s, 'crs')]), 'free', tl(fr)), 'next_id', g(s, 'next_id') + 1)
        s1 = if (kind == 0) { s0 } else { p(s0, key, g(s0, key) + 1) }
        s2 = p(s1, 'maxgen', if (gen > g(s1, 'maxgen')) { gen } else { g(s1, 'maxgen') })
        if (kind == 0 || kind == 4) { s2 } else { p(s2, 'evs', [[7, g(c, 'slot'), Math.round(nth(g(c, 'ph'), 6)), gen, kind, g(c, 'nn')] | g(s2, 'evs')]) }
    }
}

# ---- the family tree: one record per creature, kept in ETS by id (the last 30000 per island)
# [id, mom, dad, gen, species, born, island, died, kids, cause, size, speed, armor, attack, sight, diet, p1, p2, p3, hue, neurons, kind]
fun lin_key(id) { k_lin + id }
fun lin_put(tab, c, s, kind) {
    ph = g(c, 'ph')
    id = g(c, 'id')
    tput(tab, lin_key(id), [id, g(c, 'mom'), g(c, 'dad'), g(c, 'gen'), g(c, 'sp'), g(s, 'tick'), g(s, 'isl'), 0, 0, 0,
        r2(nth(ph, 0)), r2(nth(ph, 1)), r2(nth(ph, 2)), r2(nth(ph, 3)), r2(nth(ph, 4)), r2(nth(ph, 5)), r2(nth(ph, 7)), r2(nth(ph, 8)), r2(nth(ph, 9)),
        Math.round(nth(ph, 6)), g(c, 'nn'), kind])
    old = id - 30000
    if (old > g(s, 'isl') * 10000000) { ets_delete(tab + lin_key(old) % 16, lin_key(old))  ets_delete(tab + (k_dead + old) % 16, k_dead + old) } else { 'x' }
}
fun set_at(l, k, v) { if (k == 0) { [v | tl(l)] } else { [hd(l) | set_at(tl(l), k - 1, v)] } }
# death info goes under its own key, written once (records are never overwritten in place)
fun lin_died(tab, c, why, tick) { tput(tab, k_dead + g(c, 'id'), [tick, g(c, 'kids'), why]) }
fun lin_kids(tab, c) {
    r = tget(tab, lin_key(g(c, 'id')))
    if (r == nil) { 'x' } else { tput(tab, lin_key(g(c, 'id')), set_at(r, 8, g(c, 'kids'))) }
}

# pedigree of one creature: [[depth, position, record]], parents above children, 4 generations up
fun ped(tab, id, depth, pos, maxd) {
    r0 = if (id > 0) { tget(tab, lin_key(id)) } else { nil }
    dd = if (r0 == nil) { nil } else { tget(tab, k_dead + id) }
    r = if (dd == nil) { r0 } else { set_at(set_at(set_at(r0, 7, hd(dd)), 8, nth(dd, 1)), 9, nth(dd, 2)) }
    if (r == nil) { [] }
    else {
        me = [[depth, pos, r]]
        if (depth >= maxd) { me }
        else {
            mom = nth(r, 1)
            dad = nth(r, 2)
            up1 = ped(tab, mom, depth + 1, pos * 2, maxd)
            up2 = if (dad != mom) { ped(tab, dad, depth + 1, pos * 2 + 1, maxd) } else { [] }
            app(me, app(up1, up2))
        }
    }
}

fun eligible(c) { g(c, 'mate') == 1 && g(c, 'e') >= nth(g(c, 'ph'), 17) && g(c, 'age') >= 120 && g(c, 'cool') <= 0 }

fun mate_tuples(crs, acc) { if (length(crs) == 0) { acc } else { c = hd(crs)  mate_tuples(tl(crs), if (eligible(c)) { [{g(c, 'x'), g(c, 'y'), g(c, 'id')} | acc] } else { acc }) } }
fun find_mate_in(crs, c, grid) {
    cands = ng_all(grid, cellc(g(c, 'x')), cellc(g(c, 'y')), g(c, 'x'), g(c, 'y'), g(c, 'id'), [])
    find_mate(cands_creatures(crs, cands, []), c, nil)
}
fun find_mate_g(crs, c) {
    cid = g(c, 'id')
    grid = gbuild(mate_tuples(crs, []), %{})
    cands = ng_all(grid, cellc(g(c, 'x')), cellc(g(c, 'y')), g(c, 'x'), g(c, 'y'), cid, [])
    find_mate(cands_creatures(crs, cands, []), c, nil)
}
# every eligible creature within 0.06 (one ring of cells covers it)
fun ng_all(grid, cx, cy, x, y, cid, acc) { na_cells(grid, app(ring(0), ring(1)), cx, cy, x, y, cid, acc) }
fun na_cells(grid, offs, cx, cy, x, y, cid, acc) {
    if (length(offs) == 0) { acc }
    else {
        o = hd(offs)
        gx = cx + elem(o, 0)
        gy = cy + elem(o, 1)
        a2 = if (gx < 0 || gy < 0 || gx > 7 || gy > 7) { acc } else { na_items(list_or_empty(map_get(grid, gy * 8 + gx)), x, y, cid, acc) }
        na_cells(grid, tl(offs), cx, cy, x, y, cid, a2)
    }
}
fun na_items(lst, x, y, cid, acc) {
    if (length(lst) == 0) { acc }
    else { t = hd(lst)  dx = elem(t, 0) - x  dy = elem(t, 1) - y  na_items(tl(lst), x, y, cid, if (elem(t, 2) != cid && dx * dx + dy * dy < 0.0036) { [elem(t, 2) | acc] } else { acc }) }
}
fun cands_creatures(crs, ids, acc) { if (length(ids) == 0) { acc } else { o = find_id(crs, hd(ids))  cands_creatures(crs, tl(ids), if (o == nil) { acc } else { [o | acc] }) } }

fun find_mate(crs, c, best) {
    if (length(crs) == 0) { best }
    else {
        o = hd(crs)
        dx = g(o, 'x') - g(c, 'x')
        dy = g(o, 'y') - g(c, 'y')
        d = Math.sqrt(dx * dx + dy * dy)
        gd = body_dist(g(c, 'ph'), g(o, 'ph'), 0)
        ok = g(o, 'id') != g(c, 'id') && d < 0.06 && eligible(o) && gd <= fmin(nth(g(c, 'ph'), 18), nth(g(o, 'ph'), 18))
        find_mate(tl(crs), c, if (ok && (best == nil || d < elem(best, 0))) { {d, o} } else { best })
    }
}

fun pay_old(crs, id, cost, kid) { upd(crs, id, fun(c) { p(p(p(c, 'e', g(c, 'e') - cost), 'cool', 220), 'kids', g(c, 'kids') + kid) }) }

# the grid of eligible mates is built once per tick
fun breed(tab, world, s, ids) { breed_g(tab, world, s, ids, gbuild(mate_tuples(g(s, 'crs'), []), %{})) }
fun breed_g(tab, world, s, ids, mgrid) {
    if (length(ids) == 0 || length(g(s, 'crs')) >= g(s, 'cap')) { s }
    else {
        c = find_id(g(s, 'crs'), hd(ids))
        if (c == nil || g(c, 'cool') > 0) { breed_g(tab, world, s, tl(ids), mgrid) }
        else {
            m = if (eligible(c)) { find_mate_in(g(s, 'crs'), c, mgrid) } else { nil }
            if (m != nil) {
                o = elem(m, 1)
                ga = gamete(g(c, 'ha'), g(c, 'hb'), nth(g(c, 'ph'), 10))
                gb = gamete(g(o, 'ha'), g(o, 'hb'), nth(g(o, 'ph'), 10))
                gen = (if (g(c, 'gen') > g(o, 'gen')) { g(c, 'gen') } else { g(o, 'gen') }) + 1
                s1 = birth(tab, world, s, ga, gb, gen, g(c, 'sp'), clampw(g(c, 'x') + gauss() * 0.02), clampw(g(c, 'y') + gauss() * 0.02), 40.0, g(c, 'id'), g(o, 'id'), 1)
                born = length(g(s1, 'crs')) > length(g(s, 'crs'))
                s2 = if (born) { p(s1, 'crs', pay(pay(g(s1, 'crs'), g(c, 'id'), 18.0, 1), g(o, 'id'), 18.0, 1)) } else { s1 }
                breed_g(tab, world, s2, tl(ids), mgrid)
            } else { if (g(c, 'e') >= 98.0 && g(c, 'age') >= 700) {
                ga = gamete(g(c, 'ha'), g(c, 'hb'), nth(g(c, 'ph'), 10))
                gb = gamete(g(c, 'ha'), g(c, 'hb'), nth(g(c, 'ph'), 10))
                s1 = birth(tab, world, s, ga, gb, g(c, 'gen') + 1, g(c, 'sp'), clampw(g(c, 'x') + gauss() * 0.02), clampw(g(c, 'y') + gauss() * 0.02), 35.0, g(c, 'id'), g(c, 'id'), 2)
                born = length(g(s1, 'crs')) > length(g(s, 'crs'))
                breed_g(tab, world, if (born) { p(s1, 'crs', pay(g(s1, 'crs'), g(c, 'id'), 75.0, 1)) } else { s1 }, tl(ids), mgrid)
            } else { breed_g(tab, world, s, tl(ids), mgrid) } }
        }
    }
}

fun pay(crs, id, cost, kid) { upd(crs, id, fun(c) { p(p(p(c, 'e', g(c, 'e') - cost), 'cool', 150), 'kids', g(c, 'kids') + kid) }) }

fun ids_of(crs) { if (length(crs) == 0) { [] } else { [g(hd(crs), 'id') | ids_of(tl(crs))] } }

# immigrants keep a dying world going: a champion's genome (selfed) or a fresh random one
fun immigrate(tab, world, s) {
    h = g(s, 'hof')
    seeds = list_or_empty(g(s, 'seeds'))
    pos = free_pos(g(s, 'isl'), 20)
    if (length(h) > 0 && rndf() < 0.6) {
        e = nth(h, rndi(length(h)))
        birth(tab, world, s, gamete(nth(e, 1), nth(e, 2), 1.0), gamete(nth(e, 1), nth(e, 2), 1.0), nth(e, 3), nth(e, 4), hd(pos), nth(pos, 1), 70.0, 0, 0, 3)
    } else { if (length(seeds) > 0) {
        e = nth(seeds, rndi(length(seeds)))
        birth(tab, world, s, new_body(fix_hap(hd(e))), new_body(fix_hap(nth(e, 1))), 0, 0, hd(pos), nth(pos, 1), 70.0, 0, 0, 3)
    } else {
        fg = founder_genome()
        birth(tab, world, s, elem(fg, 0), elem(fg, 1), 0, 0, hd(pos), nth(pos, 1), 70.0, 0, 0, 3)
    } }
}

# a new world is colonised by a few ancestral lineages, each founder a variant of one
fun ancestors(k) { if (k <= 0) { [] } else { [if (k <= 2) { hunter_hap() } else { random_hap() } | ancestors(k - 1)] } }

# a meat-eating, spiky body plan; its brain is as random as everyone else's
fun hunter_hap() {
    h = random_hap()
    p(h, 'b', set_locus(set_locus(set_locus(g(h, 'b'), 5, 0.8), 3, 1.4), 0, 1.2))
}
fun set_locus(b, k, v) { if (k == 0) { [[v, nth(hd(b), 1)] | tl(b)] } else { [hd(b) | set_locus(tl(b), k - 1, v)] } }
# Evolution 3 brains (they already steer to food) in brand-new random bodies. The body loci
# 0-4 mean different things here (scale, rhythm, muscle strength, spike sharpness, eye acuity), so
# they are drawn fresh; diet, looks, mutation rate, the learning rule and mating genes come along.
# keep the seed brains in the island's state (also after resuming from a checkpoint), for immigrants
fun load_seeds(s) {
    path = ck_dir ++ "/brains.json"
    if (file_exists(path) != 'true') { s }
    else { d = json_decode(file_read(path))  if (d == nil) { s } else { p(s, 'seeds', list_or_empty(g(d, 'cr'))) } }
}
fun seeded_founders(tab, world, s, k) {
    path = ck_dir ++ "/brains.json"
    if (file_exists(path) != 'true') { founders(tab, world, s, k) }
    else {
        d = json_decode(file_read(path))
        lst = if (d == nil) { [] } else { list_or_empty(g(d, 'cr')) }
        if (length(lst) == 0) { founders(tab, world, s, k) } else { sf_loop(tab, world, p(s, 'seeds', lst), k, lst) }
    }
}
fun sf_loop(tab, world, s, k, lst) {
    if (k <= 0) { s }
    else {
        e = nth(lst, rndi(length(lst)))
        ha = new_body(fix_hap(hd(e)))
        hb = new_body(fix_hap(nth(e, 1)))
        pos = free_pos(g(s, 'isl'), 20)
        sf_loop(tab, world, birth(tab, world, s, ha, hb, 0, 0, hd(pos), nth(pos, 1), 70.0, 0, 0, 3), k - 1, lst)
    }
}
fun new_body(h) {
    fresh = rand_body(0)
    %{b: app(Std.take(fresh, 5), drop_n(g(h, 'b'), 5)), n: g(h, 'n'), c: g(h, 'c'), m: rand_morph(2 + rndi(3), [])}
}
fun drop_n(l, k) { if (k <= 0 || length(l) == 0) { l } else { drop_n(tl(l), k - 1) } }

fun founders(tab, world, s, k) { founders_from(tab, world, s, k, ancestors(6)) }
fun founders_from(tab, world, s, k, ancs) {
    if (k <= 0) { s }
    else {
        a = nth(ancs, k % length(ancs))
        pos = free_pos(g(s, 'isl'), 20)
        s1 = birth(tab, world, s, mutate_hap(a, 1.0), mutate_hap(a, 1.0), 0, 0, hd(pos), nth(pos, 1), 70.0, 0, 0, 3)
        founders_from(tab, world, s1, k - 1, ancs)
    }
}
fun immigrate_fresh(tab, world, s) {
    fg = founder_genome()
    pos = free_pos(g(s, 'isl'), 20)
    birth(tab, world, s, elem(fg, 0), elem(fg, 1), 0, 0, hd(pos), nth(pos, 1), 70.0, 0, 0, 3)
}

# ---- species: nearest type specimen within distance 1.1, else a new species ----
fun sp_find(sps, ph) {
    if (length(sps) == 0) { nil }
    else { r = hd(sps)  if (body_dist(nth(r, 1), ph, 0) < 1.1) { r } else { sp_find(tl(sps), ph) } }
}

fun speciate(s, crs, sps, acc, t) {
    if (length(crs) == 0) { {acc, sps, t} }
    else {
        c = hd(crs)
        cur = find_sp(sps, g(c, 'sp'))
        keep = cur != nil && body_dist(nth(cur, 1), g(c, 'ph'), 0) < 1.1
        r = if (keep) { cur } else { sp_find(sps, g(c, 'ph')) }
        if (r != nil) { speciate(s, tl(crs), sps, [p(c, 'sp', hd(r)) | acc], t) }
        else {
            sid = elem(t, 0)
            sps2 = app(sps, [[sid, g(c, 'ph'), Math.round(nth(g(c, 'ph'), 6)), g(s, 'tick')]])
            speciate(s, tl(crs), sps2, [p(c, 'sp', sid) | acc], {sid + 1, [[9, g(c, 'slot'), Math.round(nth(g(c, 'ph'), 6)), sid, g(c, 'sp'), 0] | elem(t, 1)]})
        }
    }
}

fun find_sp(sps, sid) { if (length(sps) == 0) { nil } else { if (hd(hd(sps)) == sid) { hd(sps) } else { find_sp(tl(sps), sid) } } }

fun sp_count(crs, sid, acc) { if (length(crs) == 0) { acc } else { sp_count(tl(crs), sid, if (g(hd(crs), 'sp') == sid) { acc + 1 } else { acc }) } }

fun prune_sps(sps, crs, keep, evs) {
    if (length(sps) == 0) { {rev(keep, []), evs} }
    else {
        r = hd(sps)
        if (sp_count(crs, hd(r), 0) > 0) { prune_sps(tl(sps), crs, [r | keep], evs) }
        else { prune_sps(tl(sps), crs, keep, [[10, 0, nth(r, 2), hd(r), 0, 0] | evs]) }
    }
}

fun species_step(s) {
    r = speciate(s, g(s, 'crs'), g(s, 'sps'), [], {g(s, 'sp_next'), []})
    crs = elem(r, 0)
    pr = prune_sps(elem(r, 1), crs, [], [])
    tree = tree_kill(tree_add(g(s, 'sptree'), elem(elem(r, 2), 1), g(s, 'tick')), elem(pr, 1), g(s, 'tick'))
    p(p(p(p(p(s, 'crs', crs), 'sps', elem(pr, 0)), 'sp_next', elem(elem(r, 2), 0)), 'sptree', cap(tree, 160)),
      'evs', app(elem(pr, 1), app(elem(elem(r, 2), 1), g(s, 'evs'))))
}

# species tree entries [species, parent species, hue, born tick, died tick (0 = alive)], newest first
fun tree_add(tree, evs, tick) {
    if (length(evs) == 0) { tree }
    else { e = hd(evs)  tree_add(if (hd(e) == 9) { [[nth(e, 3), nth(e, 4), nth(e, 2), tick, 0] | tree] } else { tree }, tl(evs), tick) }
}
fun tree_kill(tree, evs, tick) {
    if (length(evs) == 0) { tree }
    else { e = hd(evs)  tree_kill(if (hd(e) == 10) { tree_mark(tree, nth(e, 3), tick) } else { tree }, tl(evs), tick) }
}
fun tree_mark(tree, sid, tick) { tm_acc(tree, sid, tick, []) }
fun tm_acc(tree, sid, tick, seen) {
    if (length(tree) == 0) { rev(seen, []) }
    else {
        r = hd(tree)
        if (hd(r) == sid && nth(r, 4) == 0) { app(rev(seen, []), [[hd(r), nth(r, 1), nth(r, 2), nth(r, 3), tick] | tl(tree)]) }
        else { tm_acc(tl(tree), sid, tick, [r | seen]) }
    }
}
fun tree_seed(sps) { if (length(sps) == 0) { [] } else { r = hd(sps)  [[hd(r), 0, nth(r, 2), nth(r, 3), 0] | tree_seed(tl(sps))] } }
fun fix_tree(l) { if (l == nil) { [] } else { rev(fh_acc(l, []), []) } }

fun species_step_unused(s) {
    s
}

fun sp_rows(sps, crs) {
    if (length(sps) == 0) { [] }
    else { r = hd(sps)  [[hd(r), sp_count(crs, hd(r), 0), nth(r, 2)] | sp_rows(tl(sps), crs)] }
}

# ------------------------------------------------------------
# Checkpoints: genomes only (brains are rebuilt from them; learned weights are not inherited)
# ------------------------------------------------------------
fun ck_creatures(crs) {
    if (length(crs) == 0) { [] }
    else { c = hd(crs)  [[g(c, 'ha'), g(c, 'hb'), g(c, 'gen'), g(c, 'sp')] | ck_creatures(tl(crs))] }
}

fun save(s, name) {
    file_mkdir("checkpoints")
    file_mkdir(ck_dir)
    data = %{v: 3, tick: g(s, 'tick'), maxgen: g(s, 'maxgen'), sp_next: g(s, 'sp_next'),
             b_sex: g(s, 'b_sex'), b_bud: g(s, 'b_bud'), b_imm: g(s, 'b_imm'),
             d_starve: g(s, 'd_starve'), d_pred: g(s, 'd_pred'), d_eaten: g(s, 'd_eaten'), d_old: g(s, 'd_old'), d_toxic: num(g(s, 'd_toxic')),
             sps: g(s, 'sps'), hof: g(s, 'hof'), hist: g(s, 'hist'), sptree: g(s, 'sptree'), mig_in: g(s, 'mig_in'), mig_out: g(s, 'mig_out'), cr: ck_creatures(g(s, 'crs'))}
    path = ck_dir ++ "/" ++ name
    file_atomic_write(path, json_encode(data))
    p(p(p(s, 'ck_tick', g(s, 'tick')), 'ck_note', name), 'evs', [[11, 0, 0, g(s, 'maxgen'), length(g(s, 'crs')), 0] | g(s, 'evs')])
}

fun fl(lst) { if (length(lst) == 0) { [] } else { [to_float(hd(lst)) | fl(tl(lst))] } }
fun fix_body(lst) { if (length(lst) == 0) { [] } else { [[to_float(hd(hd(lst))), to_float(nth(hd(lst), 1))] | fix_body(tl(lst))] } }
fun fix_ns(lst) { if (length(lst) == 0) { [] } else { n = hd(lst)  [[to_int(hd(n)), to_int(nth(n, 1)), to_float(nth(n, 2)), to_float(nth(n, 3))] | fix_ns(tl(lst))] } }
fun fix_cs(lst) { if (length(lst) == 0) { [] } else { c = hd(lst)  [[to_int(hd(c)), to_int(nth(c, 1)), to_float(nth(c, 2))] | fix_cs(tl(lst))] } }
fun cap(l, k) { if (length(l) > k) { Std.take(l, k) } else { l } }
fun fix_m(l, acc) { if (l == nil || length(l) == 0) { rev(acc, []) } else { x = hd(l)  fix_m(tl(l), [[to_int(hd(x)), to_int(nth(x, 1)), to_float(nth(x, 2)), to_float(nth(x, 3)), to_float(nth(x, 4)), to_int(nth(x, 5)), to_int(nth(x, 6)), to_float(nth(x, 7))] | acc]) } }
fun fix_hap(h) { %{b: fix_body(g(h, 'b')), n: cap(fix_ns(g(h, 'n')), nmax), c: cap(fix_cs(g(h, 'c')), cmax), m: fix_m(g(h, 'm'), [])} }
fun fix_sps(lst) { if (length(lst) == 0) { [] } else { r = hd(lst)  [[to_int(hd(r)), fl(nth(r, 1)), to_int(nth(r, 2)), to_int(nth(r, 3))] | fix_sps(tl(lst))] } }
fun fix_hof(lst) {
    if (length(lst) == 0) { [] }
    else { e = hd(lst)  [[to_float(hd(e)), fix_hap(nth(e, 1)), fix_hap(nth(e, 2)), to_int(nth(e, 3)), to_int(nth(e, 4)), to_int(nth(e, 5))] | fix_hof(tl(lst))] }
}

fun load_crs(tab, world, s, lst) {
    if (length(lst) == 0) { s }
    else {
        e = hd(lst)
        pos = free_pos(g(s, 'isl'), 20)
        load_crs(tab, world, birth(tab, world, s, fix_hap(hd(e)), fix_hap(nth(e, 1)), to_int(nth(e, 2)), to_int(nth(e, 3)), hd(pos), nth(pos, 1), 70.0, 0, 0, 0), tl(lst))
    }
}

fun load(tab, world, s, name) {
    path = ck_dir ++ "/" ++ name
    if (file_exists(path) != 'true') { s }
    else {
        d = json_decode(file_read(path))
        if (d == nil || g(d, 'cr') == nil) { s }
        else {
            kill_all(g(s, 'crs'))
            isl = g(s, 'isl')
            w0 = new_world(isl)
            w1 = p(p(p(p(p(p(p(p(p(p(p(p(w0, 'tick', to_int(g(d, 'tick'))), 'maxgen', to_int(g(d, 'maxgen'))), 'sp_next', to_int(g(d, 'sp_next'))),
                  'b_sex', to_int(g(d, 'b_sex'))), 'b_bud', to_int(g(d, 'b_bud'))), 'b_imm', to_int(g(d, 'b_imm'))),
                  'd_starve', to_int(g(d, 'd_starve'))), 'd_pred', to_int(g(d, 'd_pred'))), 'd_eaten', to_int(g(d, 'd_eaten'))), 'd_old', to_int(g(d, 'd_old'))), 'd_toxic', to_int(num(g(d, 'd_toxic')))),
                  'sps', fix_sps(g(d, 'sps')))
            spn = to_int(g(d, 'sp_next'))
            tr = fix_tree(g(d, 'sptree'))
            w2a = p(p(p(p(w1, 'hof', fix_hof(g(d, 'hof'))), 'init', 1), 'ck_note', "resumed " ++ name), 'hist', fix_hist(g(d, 'hist')))
            w2 = p(p(p(p(w2a, 'sp_next', if (spn > isl * 100000) { spn } else { isl * 100000 + 1 }), 'sptree', if (length(tr) == 0) { tree_seed(g(w2a, 'sps')) } else { tr }),
                   'mig_in', to_int(num(g(d, 'mig_in')))), 'mig_out', to_int(num(g(d, 'mig_out'))))
            w3 = load_crs(tab, world, w2, g(d, 'cr'))
            p(p(w3, 'ck_tick', g(w3, 'tick')), 'evs', [[12, 0, 0, g(w3, 'maxgen'), length(g(w3, 'crs')), 0] | g(w3, 'evs')])
        }
    }
}

fun kill_all(crs) { if (length(crs) == 0) { 'ok' } else { kill_brain(hd(crs))  kill_all(tl(crs)) } }

# ------------------------------------------------------------
# The world loop
# ------------------------------------------------------------
fun ck_name(isl) { "island-" ++ to_string(isl) ++ ".json" }

# each island is its own world process; they run in parallel on separate schedulers
fun world_loop(tab, s) {
    isl = g(s, 'isl')
    cmd = cget(tab, k_isl + 200 + isl)
    if (cmd != nil) { cput(tab, k_isl + 200 + isl, nil) } else { 'x' }
    if (g(s, 'init') == 0) {
        cput(tab, k_isl + 300 + isl, self())
        own = ck_dir ++ "/" ++ ck_name(isl)
        e = env(isl)
        seed = ck_dir ++ "/" ++ ck_name(e)
        s1 = if (file_exists(own) == 'true') { load(tab, self(), s, ck_name(isl)) }
             else { if (e >= 4) { s } else { if (file_exists(seed) == 'true') { load(tab, self(), s, ck_name(e)) } else { load(tab, self(), s, "latest.json") } } }
        s2 = if (length(g(s1, 'crs')) == 0) { seeded_founders(tab, self(), p(s1, 'init', 1), 50) } else { load_seeds(s1) }
        drain_acks()
        world_loop(tab, p(s2, 'init', 1))
    } else { if (cmd == 'reset') {
        kill_all(g(s, 'crs'))
        drain_acks()
        world_loop(tab, founders(tab, self(), p(new_world(isl), 'init', 1), 50))
    } else { if (cmd == 'load') {
        s1 = load(tab, self(), s, ck_name(isl))
        drain_acks()
        world_loop(tab, s1)
    } else {
        s0 = if (cmd == 'save') { save(s, ck_name(isl)) } else { s }
        world_loop(tab, step(tab, s0))
    } } }
}

# migrants arrive as messages from other island processes
fun save_creature(c, s) {
    file_mkdir("checkpoints")
    file_mkdir(ck_dir)
    file_mkdir(ck_dir ++ "/creatures")
    path = ck_dir ++ "/creatures/creature-" ++ to_string(g(c, 'id')) ++ ".json"
    data = %{id: g(c, 'id'), island: g(s, 'isl'), env: env(g(s, 'isl')), gen: g(c, 'gen'), species: g(c, 'sp'), age: g(c, 'age'), kids: g(c, 'kids'),
             eaten: g(c, 'eaten'), nodes: g(c, 'nnodes'), mass: g(c, 'mass'), neurons: g(c, 'nn'), synapses: g(c, 'nc'), tick: g(s, 'tick'),
             ha: g(c, 'ha'), hb: g(c, 'hb')}
    file_atomic_write(path, json_encode(data))
    eprint("[evolve4] saved " ++ path)
}

fun recv_migrants(tab, world, s) {
    receive {
        {'mig', ha, hb, gen, sp, from, fromid} ->
            pos = free_pos(g(s, 'isl'), 20)
            s1 = birth(tab, world, s, ha, hb, gen, sp, hd(pos), nth(pos, 1), 65.0, fromid, fromid, 4)
            arrived = length(g(s1, 'crs')) > length(g(s, 'crs'))
            recv_migrants(tab, world, if (arrived) { p(s1, 'evs', [[15, 0, Math.round(nth(g(hd(g(s1, 'crs')), 'ph'), 6)), gen, from, 0] | g(s1, 'evs')]) } else { s1 })
        {'savecr', id} ->
            c = find_id(g(s, 'crs'), id)
            if (c == nil) { 'x' } else { save_creature(c, s) }
            recv_migrants(tab, world, s)
        after 0 { s }
    }
}

# now and then an adult swims off to another island: its genome travels as a message
fun emigrate(tab, s, tick) {
    isl = g(s, 'isl')
    crs = g(s, 'crs')
    # while the Toxic Marsh is nearly empty, the other islands send it colonists four times as often
    grp = isl / 4
    target = grp * 4 + 1
    marsh = cget(tab, k_isl + 400 + target)
    marsh_low = env(target) == 1 && isl != target && target < nisl(tab) && marsh != nil && nth(marsh, 1) < 10
    normal = tick % 700 == (isl * 175) % 700 && rndf() < 0.7
    rescue = marsh_low && tick % 175 == (isl * 43) % 175
    due = (normal || rescue) && length(crs) > 20 && nisl(tab) > grp * 4 + 1
    if (due == false) { s }
    else {
        c = nth(crs, rndi(length(crs)))
        gsize = if (grp * 4 + 4 <= nisl(tab)) { 4 } else { nisl(tab) - grp * 4 }
        dest = if (rescue) { target } else { grp * 4 + (isl % 4 + 1 + rndi(gsize - 1)) % gsize }
        pid = cget(tab, k_isl + 300 + dest)
        if (pid == nil || g(c, 'age') < 300) { s }
        else {
            send(pid, {'mig', g(c, 'ha'), g(c, 'hb'), g(c, 'gen'), g(c, 'sp'), isl, g(c, 'id')})
            kill_brain(c)
            lin_died(tab, c, 14, tick)
            s1 = p(p(p(s, 'crs', remove_id(crs, g(c, 'id'))), 'free', [g(c, 'slot') | g(s, 'free')]), 'mig_out', g(s, 'mig_out') + 1)
            p(s1, 'evs', [[14, g(c, 'slot'), Math.round(nth(g(c, 'ph'), 6)), g(c, 'gen'), dest, 0] | g(s1, 'evs')])
        }
    }
}
fun remove_id(crs, id) { if (length(crs) == 0) { [] } else { if (g(hd(crs), 'id') == id) { tl(crs) } else { [hd(crs) | remove_id(tl(crs), id)] } } }

fun nsp_alive(s) { length(g(s, 'sps')) }

fun step(tab, s0x) {
    t0 = timestamp()
    isl = g(s0x, 'isl')
    cput(tab, k_isl + 100 + isl, t0)
    s = recv_migrants(tab, self(), s0x)
    sp = if (num(cget(tab, 'speed')) < 1) { 1 } else { num(cget(tab, 'speed')) }
    plast = num(cget(tab, 'plast'))
    s0 = p(s, 'pred_on', num(cget(tab, 'pred_on')))
    drain_acks()
    oth = mk_oth(g(s0, 'crs'), [])
    s0o = p(p(p(s0, 'oth', oth), 'cg', gbuild(oth, %{})), 'pg', gbuild(plant_tuples(g(s0, 'plants'), []), %{}))
    crs0 = sense_par(self(), s0o, g(s0, 'crs'), plast)
    left = wait_acks(count_neurons(crs0, 0), 0)
    crs1 = act_all(tab, crs0, [])
    if (g(s, 'tick') % 16 == 0) { flee_pass(tab, isl, gbuild(mk_oth(crs1, []), %{}), crs1) } else { 'x' }
    s1 = feed_all(p(s0, 'crs', []), crs1, [])
    crs2 = contact_step(g(s1, 'crs'))
    s2 = p(s1, 'crs', crs2)
    s3 = reap(tab, p(p(p(s2, 'crs', []), 'meat', age_meat(g(s2, 'meat'))), 'plants', grow_plants(g(s2, 'isl'), g(s2, 'plants'), g(s2, 'tick'))), map_vitals(g(s2, 'crs'), []), [])
    # a full island cannot take a child: skip mate search and meiosis entirely (they were most of the tick)
    full_isl = length(g(s3, 'crs')) >= g(s3, 'cap') || length(g(s3, 'free')) == 0
    s4a = if (full_isl) { s3 } else { breed(tab, self(), s3, ids_of(g(s3, 'crs'))) }
    tick = g(s4a, 'tick') + 1
    s4 = emigrate(tab, s4a, tick)
    # the Toxic Marsh (island 1) gets no random immigrants: only real migrants from the other islands,
    # so whatever lives there has to adapt to the vents itself
    s5 = if (length(g(s4, 'crs')) < 20 && tick % 30 == 0 && env(g(s4, 'isl')) != 1) { immigrate(tab, self(), s4) } else { s4 }
    s6a = if (tick % 40 == 0) { species_step(s5) } else { s5 }
    s6 = if (tick % 500 == 0) { p(p(s6a, 'hist', cap([app(hist_sample(s6a, tick), flee_sample(tab, s6a)) | g(s6a, 'hist')], 400)), 'eaten_mark', g(s6a, 'd_eaten')) } else { s6a }
    s7 = if (tick - g(s6, 'ck_tick') >= 4000) { save(s6, ck_name(isl)) } else { s6 }
    if (tick % 20 == 0 && isl == 0) { cput(tab, 'procs', num(map_get(swarm_stats(), 'processes'))) } else { 'x' }
    if (tick % 20 == 0) { cput(tab, k_isl + 400 + isl, [isl, length(g(s7, 'crs')), nsp_alive(s7), g(s7, 'maxgen'), tick, g(s7, 'mig_in'), g(s7, 'mig_out'), forage_of(g(s7, 'crs'))]) } else { 'x' }
    every = 1
    # every viewer sends a heartbeat for the island it watches; an island streams full frames while anyone watches it
    viewed = timestamp() - num(cget(tab, k_isl + 600 + isl)) < 6000
    emit = viewed && tick % every == 0
    if (emit) { frame(tab, s7, tick, left, sp) } else { 'skip' }
    if (viewed == false && tick % (every * 4) == 0) { mini(s7) } else { 'x' }
    spent = timestamp() - t0
    period = if (sp == 1) { tick_ms } else { if (sp == 2) { 10 } else { 0 } }
    if (spent < period) { sleep(period - spent) } else { 'late' }
    p(p(s7, 'tick', tick), 'evs', if (emit) { [] } else { g(s7, 'evs') })
}

# ------------------------------------------------------------
# Frames
# ------------------------------------------------------------
fun r3(v) { Math.round(v * 1000.0) }
fun r2(v) { Math.round(v * 100.0) }

fun cr_row(c) {
    ph = g(c, 'ph')
    [g(c, 'slot'), g(c, 'id'), g(c, 'sp'), Math.round(nth(ph, 6)), r3(g(c, 'x') / WS), r3(g(c, 'y') / WS), r3(g(c, 'hx')), r3(g(c, 'hy')),
     Math.round(g(c, 'e')), Math.round(g(c, 'h')), r2(nth(ph, 0)), r2(nth(ph, 1)), r2(nth(ph, 2)), r2(nth(ph, 3)), r2(nth(ph, 4)),
     r2(nth(ph, 5)), r2(nth(ph, 7)), r2(nth(ph, 8)), r2(nth(ph, 9)), r2(g(c, 'sig')), g(c, 'bite'), g(c, 'mate'),
     g(c, 'gen'), g(c, 'age'), g(c, 'kids'), g(c, 'kills'), g(c, 'nn'), g(c, 'nc'), g(c, 'pain'), Math.round(nth(ph, 11) * 1000.0),
     body_flat(g(c, 'spec'), g(c, 'nodes'), []), r2(numf(g(c, 'mass'))), num(g(c, 'nnodes')), r2(numf(g(c, 'sight'))), Math.round(numf(g(c, 'pw'))),
     [num(g(c, 'nspk')), num(g(c, 'narm')), num(g(c, 'nfin')), num(g(c, 'nmou')), num(g(c, 'nmus'))]]
}

fun body_flat(spec, nodes, acc) {
    if (length(spec) == 0) { rev(acc, []) }
    else {
        sp = hd(spec)
        n = hd(nodes)
        body_flat(tl(spec), tl(nodes), [r3(elem(n, 1) / WS), r3(elem(n, 0) / WS), elem(sp, 2), Math.round(elem(sp, 0) * 10000.0), elem(sp, 1) | acc])
    }
}

fun cr_rows(crs) { if (length(crs) == 0) { [] } else { [cr_row(hd(crs)) | cr_rows(tl(crs))] } }

fun plant_pts(lst) { rev(pp_acc(lst, []), []) }
fun pp_acc(lst, acc) {
    if (length(lst) == 0) { acc }
    else { it = hd(lst)  pp_acc(tl(lst), if (nth(it, 2) > 0) { acc } else { [[r3(hd(it) / WS), r3(nth(it, 1) / WS)] | acc] }) }
}
fun meat_pts(lst) { rev(mp_acc(lst, []), []) }
fun mp_acc(lst, acc) { if (length(lst) == 0) { acc } else { it = hd(lst)  mp_acc(tl(lst), [[r3(hd(it) / WS), r3(nth(it, 1) / WS), Math.round(nth(it, 2))] | acc]) } }
fun pred_pts(lst) { if (length(lst) == 0) { [] } else { pr = hd(lst)  [[r3(hd(pr)), r3(nth(pr, 1)), nth(pr, 2), nth(pr, 3)] | pred_pts(tl(lst))] } }
fun pois_pts(lst) { rev(po_acc(lst, []), []) }
fun po_acc(lst, acc) { if (length(lst) == 0) { acc } else { it = hd(lst)  po_acc(tl(lst), [[r3(hd(it) / WS), r3(nth(it, 1) / WS)] | acc]) } }
fun meadows(i, k, t) { if (k >= meadow_count(i)) { [] } else { c = patch_center(i, k, t)  [[r3(elem(c, 0) / WS), r3(elem(c, 1) / WS), r3(0.17 / WS)] | meadows(i, k + 1, t)] } }
fun env_list(k, n) { if (k >= n) { [] } else { [env(k) | env_list(k + 1, n)] } }
fun maps(k) { if (k >= 8) { [] } else { [[obst_pts(obstacles(k)), obst_pts(vents(k)), obst_pts(kelp(k))] | maps(k + 1)] } }

fun obst_pts(lst) { if (length(lst) == 0) { [] } else { o = hd(lst)  [[r3(hd(o) / WS), r3(nth(o, 1) / WS), r3(nth(o, 2) / WS)] | obst_pts(tl(lst))] } }

fun sum_ph(crs, k, acc) { if (length(crs) == 0) { acc } else { sum_ph(tl(crs), k, acc + nth(g(hd(crs), 'ph'), k)) } }
fun sum_k(crs, k, acc) { if (length(crs) == 0) { acc } else { sum_k(tl(crs), k, acc + to_float(g(hd(crs), k))) } }
fun mean_ph(crs, k) { if (length(crs) == 0) { 0.0 } else { sum_ph(crs, k, 0.0) / to_float(length(crs)) } }
fun mean_k(crs, k) { if (length(crs) == 0) { 0.0 } else { sum_k(crs, k, 0.0) / to_float(length(crs)) } }

fun by_slot(crs, slot) { if (length(crs) == 0) { nil } else { if (g(hd(crs), 'slot') == slot) { hd(crs) } else { by_slot(tl(crs), slot) } } }

fun best_slot(crs, best) {
    if (length(crs) == 0) { if (best == nil) { -1 } else { g(best, 'slot') } }
    else { c = hd(crs)  best_slot(tl(crs), if (best == nil || g(c, 'kids') * 1000 + g(c, 'age') > g(best, 'kids') * 1000 + g(best, 'age')) { c } else { best }) }
}

fun forage_of(crs) { Math.round(sum_k(crs, 'eaten', 0.0) * 100000.0 / (sum_k(crs, 'age', 0.0) + 1.0)) }

# [tick, generation, population, foraging*100, neurons per brain*100, attack*100, plasticity*1000, size*100, armor*100, species, diet*100]
fun hist_sample(s, tick) {
    crs = g(s, 'crs')
    [tick, g(s, 'maxgen'), length(crs), forage_of(crs), r2(mean_k(crs, 'nn')), r2(mean_ph(crs, 3)), Math.round(mean_ph(crs, 11) * 1000.0),
     r2(mean_ph(crs, 0)), r2(mean_ph(crs, 2)), length(g(s, 'sps')), r2(mean_ph(crs, 5))]
}

fun flee_sample(tab, s) {
    isl = g(s, 'isl')
    n = num(cget(tab, k_isl + 501 + isl * 2))
    fl = if (n > 0) { numf(cget(tab, k_isl + 500 + isl * 2)) / to_float(n) } else { 0.0 }
    cput(tab, k_isl + 500 + isl * 2, 0.0)
    cput(tab, k_isl + 501 + isl * 2, 0)
    pop = length(g(s, 'crs'))
    eaten = g(s, 'd_eaten') - num(g(s, 'eaten_mark'))
    [Math.round(fl * 1000.0), if (pop > 0) { Math.round(to_float(eaten) * 100000.0 / (to_float(pop) * 500.0)) } else { 0 }]
}

fun ints(l) { rev(ints_acc(l, []), []) }
fun ints_acc(l, acc) { if (length(l) == 0) { acc } else { ints_acc(tl(l), [to_int(hd(l)) | acc]) } }
fun fix_hist(l) { if (l == nil) { [] } else { rev(fh_acc(l, []), []) } }
fun fh_acc(l, acc) { if (length(l) == 0) { acc } else { fh_acc(tl(l), [ints(hd(l)) | acc]) } }

fun r2l(lst) { if (length(lst) == 0) { [] } else { [r2(hd(lst)) | r2l(tl(lst))] } }

# body loci normalised 0..100 with dominance 0..100, for the chromosome view
fun kar(b, k) {
    if (length(b) == 0) { [] }
    else { [[Math.round((hd(hd(b)) - lo(k)) / (hi(k) - lo(k)) * 100.0), Math.round(nth(hd(b), 1) * 100.0)] | kar(tl(b), k + 1)] }
}

fun net_edges(tab, c, k, inls) {
    if (length(inls) == 0) { [] }
    else {
        cur = tget(tab, k_w + g(c, 'slot') * nmax + k)
        app(edges_of(hd(inls), if (cur == nil) { hd(inls) } else { cur }, k), net_edges(tab, c, k + 1, tl(inls)))
    }
}
fun edges_of(innate, cur, dst) {
    if (length(innate) == 0 || length(cur) == 0) { [] }
    else { e = hd(innate)  [[hd(e), dst, nth(e, 1), r2(nth(e, 2)), r2(nth(hd(cur), 2))] | edges_of(tl(innate), tl(cur), dst)] }
}

fun isl_sums(tab, k) { if (k >= nisl(tab)) { [] } else { [list_or_empty(cget(tab, k_isl + 400 + k)) | isl_sums(tab, k + 1)] } }

fun mini_rows(crs) { if (length(crs) == 0) { [] } else { c = hd(crs)  [[r3(g(c, 'x') / WS), r3(g(c, 'y') / WS), Math.round(nth(g(c, 'ph'), 6))] | mini_rows(tl(crs))] } }
fun mini(s) {
    LiveView.broadcast("evolve4", {'frame', json_encode(%{t: "ev", n: "mini", d: %{isl: g(s, 'isl'), cr: mini_rows(g(s, 'crs')), tick: g(s, 'tick')}})})
}

fun frame(tab, s, tick, left, sp) {
    st = swarm_stats()
    crs = g(s, 'crs')
    isl_f = g(s, 'isl')
    want = num(cget(tab, k_isl + 700 + isl_f))
    sel = if (by_slot(crs, want) != nil) { want } else { best_slot(crs, nil) }
    if (sel != want) { cput(tab, k_isl + 700 + isl_f, sel) } else { 'x' }
    sc = if (sel >= 0) { by_slot(crs, sel) } else { nil }
    full = tick % 15 == 0 || num(cget(tab, k_isl + 800 + isl_f)) == 1
    if (full) { cput(tab, k_isl + 800 + isl_f, 0) } else { 'x' }
    nn = count_neurons(crs, 0)
    nc = count_conns(crs, 0)
    LiveView.broadcast("evolve4", {'frame', json_encode(%{t: "ev", n: "frame", d: %{
        tick: tick, cr: cr_rows(crs), sel: sel, isl: g(s, 'isl'), isls: isl_sums(tab, 0), mig_in: g(s, 'mig_in'), mig_out: g(s, 'mig_out'),
        ped: if (sc != nil && full) { ped(tab, g(sc, 'id'), 0, 0, 4) } else { nil },
        sptree: if (tick % 60 == 0) { g(s, 'sptree') } else { nil },
        acts: if (sc != nil) { r2l(read_acts(tab, sel, 0, g(sc, 'nn'))) } else { [] },
        sens: if (sc != nil) { r2l(list_or_empty(g(sc, 'sv'))) } else { [] },
        net: if (sc != nil && full) { %{id: g(sc, 'id'), types: g(sc, 'types'), e: net_edges(tab, sc, 0, g(sc, 'inl'))} } else { nil },
        kar: if (sc != nil && full) { %{a: kar(g(g(sc, 'ha'), 'b'), 0), b: kar(g(g(sc, 'hb'), 'b'), 0),
                                        an: [length(g(g(sc, 'ha'), 'n')), length(g(g(sc, 'ha'), 'c'))], bn: [length(g(g(sc, 'hb'), 'n')), length(g(g(sc, 'hb'), 'c'))],
                                        mom: g(sc, 'mom'), dad: g(sc, 'dad')} } else { nil },
        plants: plant_pts(g(s, 'plants')), meat: meat_pts(g(s, 'meat')), preds: [],
        obst: if (tick % 30 == 0 || full) { obst_pts(obstacles(g(s, 'isl'))) } else { nil }, vents: if (tick % 30 == 0 || full) { obst_pts(vents(g(s, 'isl'))) } else { nil },
        meadows: if (tick % 30 == 0 || full) { meadows(g(s, 'isl'), 0, tick) } else { nil }, env: env(g(s, 'isl')), kelp: if (tick % 30 == 0 || full) { obst_pts(kelp(g(s, 'isl'))) } else { nil }, maps: if (tick % 60 == 0) { maps(0) } else { nil }, envs: env_list(0, nisl(tab)), poison: pois_pts(g(s, 'poison')), ws: WS,
        pop: length(crs), maxgen: g(s, 'maxgen'), b_sex: g(s, 'b_sex'), b_bud: g(s, 'b_bud'), b_imm: g(s, 'b_imm'),
        d_starve: g(s, 'd_starve'), d_pred: g(s, 'd_pred'), d_eaten: g(s, 'd_eaten'), d_old: g(s, 'd_old'), d_toxic: num(g(s, 'd_toxic')),
        sps: sp_rows(g(s, 'sps'), crs),
        mean: [r2(mean_ph(crs, 0)), r2(mean_ph(crs, 1)), r2(mean_ph(crs, 2)), r2(mean_ph(crs, 3)), r2(mean_ph(crs, 4)), r2(mean_ph(crs, 5)),
               r2(mean_ph(crs, 10)), Math.round(mean_ph(crs, 11) * 1000.0), r2(mean_k(crs, 'nn')), r2(mean_k(crs, 'nc'))],
        forage: forage_of(crs), hist: if (tick % 60 == 0) { g(s, 'hist') } else { nil },
        nn: nn, nc: nc, procs: num(map_get(st, 'processes')), late: left,
        speed: sp, pred_on: g(s, 'pred_on'), plast: num(cget(tab, 'plast')),
        ck: g(s, 'ck_note'), ck_tick: g(s, 'ck_tick'), hof: length(g(s, 'hof')),
        evs: g(s, 'evs')
    }})})
}

# ------------------------------------------------------------
# Commands and view
# ------------------------------------------------------------
fun inbox(tab) {
    receive {
        {'set', k, v} ->
            cput(tab, k, v)
            inbox(tab)
        {'toggle', k} ->
            cput(tab, k, 1 - num(cget(tab, k)))
            inbox(tab)
        {'cmd', c} ->
            cmd_all(tab, c, 0)
            inbox(tab)
        {'savecr', isl, id} ->
            pid = cget(tab, k_isl + 300 + isl)
            if (pid == nil) { 'x' } else { send(pid, {'savecr', id}) }
            inbox(tab)
        _o -> inbox(tab)
    }
}

fun cmd_all(tab, c, k) { if (k >= nisl(tab)) { 'ok' } else { cput(tab, k_isl + 200 + k, c)  cmd_all(tab, c, k + 1) } }

fun save_cr_event(isl, id) {
    a = whereis('evolve4_in')
    if (a == nil) { 'noop' } else { send(a, {'savecr', isl, id}) }
}

fun inbox_send(msg) {
    a = whereis('evolve4_in')
    if (a == nil) { 'noop' } else { send(a, msg) }
}

fun mount(params) {
    if (LiveView.connected(params) == 'true') { LiveView.subscribe("evolve4") } else { 'noop' }
    %{}
}

fun handle_event(name, value, assigns) {
    if (name == "sel") { si = to_int(num(map_get(value, 'isl')))  inbox_send({'set', k_isl + 700 + si, to_int(map_get(value, 'slot'))})  inbox_send({'set', k_isl + 800 + si, 1}) }
    else { if (name == "speed") { inbox_send({'set', 'speed', to_int(map_get(value, 'k'))}) }
    else { if (name == "pred") { inbox_send({'toggle', 'pred_on'}) }
    else { if (name == "plast") { inbox_send({'toggle', 'plast'}) }
    else { if (name == "save") { inbox_send({'cmd', 'save'}) }
    else { if (name == "load") { inbox_send({'cmd', 'load'}) }
    else { if (name == "reset") { inbox_send({'cmd', 'reset'}) }
    else { if (name == "savecr") { save_cr_event(to_int(map_get(value, 'isl')), to_int(map_get(value, 'id'))) }
    else { if (name == "view") { inbox_send({'set', k_isl + 600 + to_int(map_get(value, 'i')), timestamp()})  if (map_get(value, 'fresh') != nil) { inbox_send({'set', k_isl + 800 + to_int(map_get(value, 'i')), 1}) } else { 'x' } }
    else { 'noop' } } } } } } } } }
    assigns
}

fun handle_info(msg, assigns) {
    conn = map_get(assigns, '_conn')
    if (conn != nil && elem(msg, 0) == 'frame') { ws_send(conn, elem(msg, 1)) } else { 'noop' }
    assigns
}

fun css() {
    "<style>" ++
    ":root{--bg:#000;--card:#0a0a0a;--line:#1c1c1c;--line2:#2c2c2c;--tx:#ededed;--mu:#8f8f8f;--mu2:#5f5f5f;--red:#ff5a5a;--green:#50e3c2;--amber:#f5a623;--violet:#a78bfa;--blue:#5aa9ff}" ++
    "*{box-sizing:border-box}html,body{height:100%;background:var(--bg);color:var(--tx);margin:0}" ++
    "body{font-family:ui-sans-serif,-apple-system,'SF Pro Text',Inter,'Segoe UI',sans-serif;-webkit-font-smoothing:antialiased;overflow:hidden}" ++
    "#live-root{height:100%;display:flex;flex-direction:column}" ++
    ".nav{height:52px;flex:none;display:flex;align-items:center;gap:14px;padding:0 20px;border-bottom:1px solid var(--line)}" ++
    ".logo{display:flex;align-items:center;gap:10px;font-weight:600;font-size:14px;white-space:nowrap}.crumb{color:var(--mu);font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}.crumb:before{content:'/';margin-right:14px;color:#3a3a3a}" ++
    ".pill{display:flex;align-items:center;gap:8px;font-size:12px;color:var(--mu);padding:5px 11px;border:1px solid var(--line2);border-radius:99px;white-space:nowrap}.ml{margin-left:auto}" ++
    ".dot{width:7px;height:7px;border-radius:50%;background:var(--green);animation:pulse 1.8s infinite}" ++
    "@keyframes pulse{70%{box-shadow:0 0 0 7px rgba(80,227,194,0)}100%{box-shadow:0 0 0 0 rgba(80,227,194,0)}}" ++
    ".main{flex:1;min-height:0;padding:14px 20px 16px;display:grid;grid-template-columns:minmax(0,1.5fr) minmax(360px,1fr);gap:14px}" ++
    ".card{background:var(--card);border:1px solid var(--line);border-radius:14px}" ++
    ".world{position:relative;overflow:hidden;background:#05070b}.world canvas{position:absolute;inset:0}" ++
    ".hud{position:absolute;left:16px;top:14px;right:16px;display:flex;align-items:flex-start;gap:12px;pointer-events:none}" ++
    ".head{font-size:13px;color:var(--mu);line-height:1.35}.head b{color:var(--tx);font-weight:600}.head .big{display:block;font-size:22px;color:var(--tx);font-weight:600;letter-spacing:-.02em}" ++
    ".seg{margin-left:auto;display:flex;background:#0d0d0d;border:1px solid var(--line2);border-radius:9px;padding:2px;pointer-events:auto}" ++
    ".seg button{font:inherit;font-size:12px;color:var(--mu);background:none;border:0;border-radius:7px;padding:5px 11px;cursor:pointer}.seg button.on{background:#ededed;color:#000}" ++
    ".legend{position:absolute;left:16px;right:16px;bottom:12px;display:flex;flex-wrap:wrap;gap:6px 14px;font-size:11.5px;color:var(--mu);pointer-events:none}" ++
    ".legend span{display:flex;align-items:center;gap:6px}.legend i{width:9px;height:9px;border-radius:2px;display:inline-block}" ++
    ".tip{position:absolute;pointer-events:none;background:rgba(12,12,14,.94);border:1px solid var(--line2);border-radius:10px;padding:9px 11px;font-size:12px;line-height:1.45;opacity:0;transition:opacity .12s;min-width:170px;backdrop-filter:blur(6px)}.tip b{font-weight:600}.tip .r{color:var(--mu)}" ++
    ".side{position:relative;min-height:0;overflow:hidden}" ++
    ".pg{position:absolute;inset:0;overflow:auto;display:flex;flex-direction:column;gap:12px;transition:transform .28s cubic-bezier(.2,.8,.2,1),opacity .2s;scrollbar-width:none}" ++
    ".pg.off{transform:translateX(24px);opacity:0;pointer-events:none}" ++
    ".side .card{padding:14px 16px;flex:none}" ++
    "h3{font-size:12.5px;font-weight:600;margin:0 0 10px;display:flex;justify-content:space-between;gap:8px}h3 span{color:var(--mu);font-weight:400}" ++
    ".ins{display:grid;grid-template-columns:1fr 1fr;gap:10px}" ++
    ".tile{border:1px solid var(--line);border-radius:11px;padding:11px 12px;background:#0d0d0d}.tile .v{font-size:22px;font-weight:600;letter-spacing:-.02em;font-variant-numeric:tabular-nums}.tile .t{font-size:12px;font-weight:600;margin-top:2px}.tile .d{font-size:11.5px;color:var(--mu);margin-top:3px;line-height:1.4}" ++
    ".sm{display:grid;grid-template-columns:1fr 1fr;gap:10px 14px}.sm .k{font-size:11.5px;color:var(--mu);display:flex;justify-content:space-between}.sm .k b{color:var(--tx);font-weight:600;font-variant-numeric:tabular-nums}.sm canvas{width:100%;height:46px;display:block;margin-top:4px}" ++
    ".note{font-size:11px;color:var(--mu2);margin-top:8px}.isls{display:grid;grid-template-columns:1fr 1fr;gap:8px}.it{border:1px solid var(--line);border-radius:11px;padding:8px;cursor:pointer;background:#0b0b0b;transition:border-color .15s,background .15s}.it:hover{border-color:#3a3a3a}.it.on{border-color:#ededed;background:#111}.it canvas{width:100%;height:84px;display:block;border-radius:7px;background:#05070b;image-rendering:pixelated}.it .nm{font-size:12px;font-weight:600;margin-top:6px}.it .st{font-size:11px;color:var(--mu);margin-top:1px}.isls.many{grid-template-columns:repeat(4,1fr);gap:6px}.isls.many .it{padding:5px;border-radius:9px}.isls.many .it canvas{height:52px}.isls.many .it .nm{font-size:10.5px;margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.isls.many .it .st{font-size:10px}" ++
    ".spr{display:grid;grid-template-columns:30px 1fr 60px;gap:10px;align-items:center;padding:5px 0;border-top:1px solid #141414;font-size:12px;cursor:pointer}.spr:first-child{border-top:0}.spr:hover{background:#0f0f0f}" ++
    ".spr canvas{width:30px;height:30px;image-rendering:pixelated}.spr .n{font-weight:600}.spr .r{color:var(--mu);font-size:11.5px}.bar{height:5px;border-radius:3px;background:#1a1a1a;overflow:hidden}.bar i{display:block;height:100%;border-radius:3px}" ++
    "#feed{font-size:12px;line-height:1.5;min-height:96px}.ev{display:flex;gap:9px;padding:2px 0;animation:in .3s ease}.ev i{width:7px;height:7px;border-radius:2px;margin-top:6px;flex:none}" ++
    "@keyframes in{from{opacity:0;transform:translateY(-4px)}to{opacity:1;transform:none}}" ++
    ".btns{display:flex;flex-wrap:wrap;gap:6px}.btn{font:inherit;font-size:12px;font-weight:500;color:var(--tx);background:#111;border:1px solid var(--line2);border-radius:8px;padding:7px 10px;cursor:pointer;transition:background .12s,border-color .12s,transform .06s}" ++
    ".btn:hover{background:#1a1a1a;border-color:#444}.btn:active{transform:scale(.97)}.btn.on{background:#ededed;color:#000;border-color:#ededed}.btn.danger{color:#ff9a9a;border-color:#4a1d1d;background:#170a0a}" ++
    ".ih{display:flex;gap:14px;align-items:center}.ih canvas{width:64px;height:64px;image-rendering:pixelated;border-radius:12px;background:#07090d;border:1px solid var(--line)}.ih .tt{font-size:18px;font-weight:600;letter-spacing:-.01em}.ih .st{font-size:12px;color:var(--mu);margin-top:2px}" ++
    ".x{margin-left:auto;align-self:flex-start;font:inherit;font-size:12px;color:var(--mu);background:#111;border:1px solid var(--line2);border-radius:8px;padding:5px 10px;cursor:pointer}.x:hover{color:var(--tx)}" ++
    ".vit{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-top:12px}.vit div{font-size:11px;color:var(--mu)}.vit b{display:block;font-size:15px;color:var(--tx);font-weight:600;font-variant-numeric:tabular-nums}" ++
    ".tr{display:grid;grid-template-columns:78px 1fr 40px;gap:8px;align-items:center;font-size:11.5px;color:var(--mu);margin:5px 0}.tr b{color:var(--tx);font-weight:500;text-align:right;font-variant-numeric:tabular-nums}" ++
    ".cvb{width:100%;display:block}.cap{font-size:11.5px;color:var(--mu);line-height:1.5;margin:8px 0 0}.cap b{color:var(--tx);font-weight:600}" ++
    ".toast{position:absolute;right:16px;bottom:40px;font-size:12px;padding:7px 11px;border-radius:9px;background:#0f1a17;border:1px solid #1d4d40;color:var(--green);opacity:0;transform:translateY(6px);transition:all .3s;pointer-events:none}.toast.show{opacity:1;transform:none}" ++
    "@media(max-width:900px){.crumb{display:none}.nav .pill:last-child{display:none}}@media(max-width:1100px){body{overflow:auto}#live-root{height:auto}.main{grid-template-columns:1fr}.world{height:620px}.side{height:900px}}" ++
    "</style>"
}

fun render(assigns) {
    LiveView.h(
        css() ++
        "<header class=\"nav\"><div class=\"logo\">" ++
        "<svg width=\"20\" height=\"20\" viewBox=\"0 0 10 10\" shape-rendering=\"crispEdges\"><path fill=\"#50e3c2\" d=\"M3 1h4v1h1v1h1v4H8v1H7v1H3V8H2V7H1V3h1V2h1z\"/><path fill=\"#05060a\" d=\"M3 4h1v1H3zM6 4h1v1H6z\"/><path fill=\"#a78bfa\" d=\"M4 6h2v1H4z\"/></svg>" ++
        "Evolution 4</div><span class=\"crumb\">bodies and brains evolved with real physics</span>" ++
        "<div class=\"pill ml\"><span class=\"dot\"></span><span id=\"o-tps\">0</span> ticks/s &middot; <span id=\"o-procs\">0</span> neuron processes</div>" ++
        "<div class=\"pill\" id=\"o-ck\">checkpoint &ndash;</div></header>" ++
        "<div class=\"main\">" ++
        "<div class=\"card world\" id=\"arena\"><canvas id=\"arena-cv\" sw-keep></canvas>" ++
        "<div class=\"hud\"><div class=\"head\" id=\"head\" sw-keep><span class=\"big\">Generation &ndash;</span>waiting for the world</div>" ++
        "<div class=\"seg\"><button data-speed=\"1\">1x</button><button data-speed=\"2\">fast</button><button data-speed=\"3\">turbo</button></div></div>" ++
        "<div class=\"legend\" id=\"legend\" sw-keep><span><i style=\"background:#50e3c2\"></i>algae (food)</span><span><i style=\"background:#c4423f\"></i>meat (the dead)</span><span><i style=\"background:#b45cf0\"></i>poison algae &amp; toxic vents (hurt)</span><span><i style=\"background:#287850\"></i>algae meadow</span><span><i style=\"background:#ff4b3a\"></i>red spikes = meat-eating hunter</span>" ++
        "<span style=\"color:#6b6b6b\">microbe: spikes = attack &middot; grey plates = armor &middot; tail = speed &middot; eye = sight &middot; glow = signalling</span></div>" ++
        "<div class=\"tip\" id=\"tip\" sw-keep></div><div class=\"toast\" id=\"toast\" sw-keep></div></div>" ++
        "<div class=\"side\">" ++
        "<div class=\"pg\" id=\"pg-story\">" ++
        "<div class=\"card\"><h3>Islands <span>separate worlds, rare migrants between them</span></h3><div class=\"isls\" id=\"isls\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>What evolution found <span id=\"ins-sub\">on this island</span></h3><div class=\"ins\" id=\"ins\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>The whole run <span id=\"run-span\">since this world began</span></h3><div class=\"sm\" id=\"sm\" sw-keep></div><div class=\"note\" id=\"run-note\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Species alive <span>click one to inspect a member</span></h3><div id=\"spl\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Species tree <span>who split from whom, over time</span></h3><canvas id=\"tree-cv\" class=\"cvb\" style=\"height:170px\" sw-keep></canvas><p class=\"cap\">Each line is a species, until it died out or now; bold = alive. A branch joined to a parent line is a real split. A diamond is a species that arrived from outside (an immigrant or a migrant from another island).</p></div>" ++
        "<div class=\"card\"><h3>What just happened</h3><div id=\"feed\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Experiment</h3><div class=\"btns\"><button class=\"btn on\" id=\"b-plast\">Learning: on</button>" ++
        "<button class=\"btn\" id=\"b-save\">Save checkpoint</button><button class=\"btn\" id=\"b-load\">Load checkpoint</button><button class=\"btn danger\" id=\"b-reset\">New random world</button></div>" ++
        "<p class=\"cap\">No fitness function, no teacher, no scripted movement: each body is grown from its genes as nodes and muscles, and it only moves if its fins push water. Every hunter is an evolved creature too. A brain is <b>built from the genes</b>, one swarmrt process per neuron. Creatures that find food and mates leave children; the rest die. Genes come in <b>two copies</b> that cross over and mutate; synapses also learn during a life by a rule that itself evolves. Turn <b>Learning</b> off to test whether that rule matters.</p></div>" ++
        "</div>" ++
        "<div class=\"pg off\" id=\"pg-insp\">" ++
        "<div class=\"card\"><div class=\"ih\"><canvas id=\"i-spr\" width=\"32\" height=\"32\" sw-keep></canvas><div><div class=\"tt\" id=\"i-title\" sw-keep>&ndash;</div><div class=\"st\" id=\"i-sub\" sw-keep></div></div><button class=\"x\" id=\"b-savecr\" style=\"margin-left:auto\">Save this creature</button><button class=\"x\" id=\"b-close\" style=\"margin-left:6px\">Back</button></div>" ++
        "<div class=\"vit\" id=\"i-vit\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Its brain <span id=\"i-bsub\"></span></h3><canvas id=\"brain-cv\" class=\"cvb\" style=\"height:300px\" sw-keep></canvas>" ++
        "<p class=\"cap\">Left: its <b>18 senses</b>. Right: its <b>5 actions</b>. Middle: neurons its genes grew. Lines are synapses (blue excites, red inhibits, dashed amber modulates learning, violet glow = changed by learning in this life). Dots moving along lines are messages between processes.</p></div>" ++
        "<div class=\"card\"><h3>Its family tree <span id=\"i-fam\"></span></h3><canvas id=\"ped-cv\" class=\"cvb\" style=\"height:230px\" sw-keep></canvas><p class=\"cap\">Parents above, grandparents above them, four generations up. A creature that budded has a single parent. Faded ancestors are dead; the word under them says how they died.</p></div>" ++
        "<div class=\"card\"><h3>Its body genes</h3><div id=\"i-traits\" sw-keep></div></div>" ++
        "<div class=\"card\"><h3>Its two chromosomes <span id=\"i-par\"></span></h3><canvas id=\"gene-cv\" class=\"cvb\" style=\"height:190px\" sw-keep></canvas>" ++
        "<p class=\"cap\">One copy from each parent. Each band is a gene; brightness is its value, the white cap its dominance. A tick below marks a gene where the two copies differ (it is <b>heterozygous</b>): hidden variation that can show up in its children.</p></div>" ++
        "</div>" ++
        "</div></div>",
        [])
}

# if the world process ever dies (a panic), start a new one: it resumes from the last checkpoint
fun watchdog(tab, isl) {
    cput(tab, k_isl + 100 + isl, timestamp())
    w = spawn(world_loop(tab, new_world(isl)))
    watch(tab, isl, w)
}

fun watch(tab, isl, w) {
    sleep(2000)
    if (timestamp() - num(cget(tab, k_isl + 100 + isl)) > 20000) {
        eprint("[evolve4] island " ++ to_string(isl) ++ " stopped responding; restarting it from its last checkpoint")
        watchdog(tab, isl)
    } else { watch(tab, isl, w) }
}

fun start_islands(tab, k) { if (k >= nisl(tab)) { 'ok' } else { spawn(watchdog(tab, k))  start_islands(tab, k + 1) } }

fun main() {
    tab = make_tables(ets_new(), 16)
    cput(tab, 'pred_on', 1)
    cput(tab, 'plast', 1)
    cput(tab, 'speed', 3)
    cput(tab, 'sel', 0 - 1)
    ne = getenv("EVOLVE_ISLANDS")
    n0 = if (ne == nil || ne == "") { 4 } else { to_int(ne) }
    cput(tab, 'n_isl', if (n0 < 1) { 1 } else { if (n0 > 48) { 48 } else { n0 } })
    cput(tab, 'view', 0)
    start_islands(tab, 0)
    register('evolve4_in', spawn(inbox(tab)))
    LiveView.start(4017, [
        {"/", %{
            title: "Evolution 4",
            js: Evolve4Js.js(),
            mount: mount,
            render: render,
            handle_event: handle_event,
            handle_info: handle_info
        }}
    ])
}
