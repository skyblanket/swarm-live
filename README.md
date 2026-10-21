# swarm-live

A production LiveView framework for **swarmrt** — server-driven reactive web UI in pure `sw`, with a shadcn-flavoured component kit (**swarmUI**).

The server holds UI state; the browser is a thin renderer. After the first paint, only the values that *changed* cross the WebSocket — never the page. A counter increment costs ~20 bytes.

## Build

(needs sibling `../swarmrt` with `bin/swc` + `bin/libswarmrt.a` built)

```sh
make            # builds bin/counter ... bin/showcase
./bin/counter   # http://localhost:4000
./bin/showcase  # http://localhost:4005 — the swarmUI gallery
```

## Files

```
src/LiveView.sw   the framework (start/serve/session, h template, diff, PubSub, presence, streams)
src/UI.sw         swarmUI — 14 shadcn-flavoured components + UI.css() design system
src/Client.sw     embedded browser client (diff protocol, morphdom, bindings, JS commands)
src/counter.sw    :4000  diff-protocol counter (the tracer bullet)
src/todo.sw       :4001  list components, sw-submit form data, live validation
src/router.sw     :4002  routes + :params + sw-link live navigation
src/chat.sw       :4003  PubSub broadcast across all sessions
src/feed.sw       :4004  stream ops + presence + a sw-js JS command
src/showcase.sw   :4005  every UI component on one live page
src/canvas.sw     :4006  shared multiplayer canvas — ink, live cursors, presence, history
src/arena.sw      :4007  Swarm Arena — 600 supervised processes on a canvas: real message comets, kills, supervisor respawns (add ?slow=8 for slow-mo)
src/flock.sw      :4008  Flock — 800 boids, each a swarmrt process; every visitor is a predator (hold to attract); live flock-order metric
src/Observer.sw   Swarm Observer — a live X-ray of the swarmrt node it runs in (process map by supervisor, backlog / busiest / biggest, scheduler load, activity feed); `Observer.view(opts)` mounts in any app
src/observer_demo.sw :4009  a node with a pipeline (slow stage backs up), crash loops, gossip and memory hogs to look at; Flock also mounts it at :4008/_observer
src/life.sw       :4011  Life at Scale — Conway's Game of Life where every cell is a supervised process (up to 160x160 = 25,600), generations are pure message passing (~10 messages per cell), kill cells and watch them self-heal, stack tens of thousands of idle processes next to it
src/brain.sw      :4012  Neuron Swarm — a spiking neural network where every neuron is a process (2.4k by default): leaky integrate-and-fire neurons spike by messaging the neurons they are wired to; four motor neurons steer a creature to food; the readout learns online (normalised delta rule with a teacher signal) and recovers from lesions
src/creature.sw   :4013  Creature — a body (energy, health), 106 senses (7 vision rays, smell, touch, pain, hunger) and a three-region brain of ~2.4k neuron processes, living among food, poison, obstacles and a predator. The readout into 4 motor neurons learns by imitating a hand-written expert (behaviour cloning, not RL); an autopilot hands control to the brain as it improves, and can be switched off
src/evolve.sw     :4014  Evolution — up to 10 creatures in one arena, each with its OWN brain of neuron processes (a birth spawns a new supervised brain, a death stops it). Genes (speed, sight, brain size, caution, hunger) are inherited with mutation and each costs energy; whoever starves or is eaten disappears, whoever has spare energy reproduces. Click a creature to watch its brain; trait and population charts show the drift. Time-lapse control. (Neuroevolution of traits + imitation learning in a lifetime, not open-ended evolution.)
src/evolve2.sw    :4015  Evolution 2 — up to 24 microbes with ten genes (speed, sight, brain size, caution, hunger, attack, armor, body size, aggression, and their own mutation rate, plus rare big mutation jumps). Spikes, shell plates, tail, eye and nucleus are drawn from the genes. Strangers can eat each other (armor cuts damage, attackers gain energy); two predators now stalk with a visible warning, chase briefly and slower than a boosting creature, then rest, so they can be evaded. Gene-pool scatter (attack vs armor) with the population mean's path. Same honesty label as Evolution: traits evolve, learning is imitation, not open-ended evolution.
src/evolve3.sw    :4016  Evolution 3 — real neuroevolution on four islands. Each island is its own world process (Green Meadows, Toxic Marsh, Lean Waters, Rich Shallows: different food, poison and vent strength), running in parallel; an adult sometimes swims to another island and its genome travels as a message. Brains are built from a diploid genome (dominance, crossover with linkage, NEAT-style neuron/synapse genes), one swarmrt process per neuron (rate, spiking, modulatory), with synapses that learn by an evolved neuromodulated rule; learned weights are not inherited. Sex or budding, speciation, no biting your own species, energy cost per neuron and synapse. Pixel-art microbes from the genome, a family tree (four generations of ancestors) and a species tree, brain and chromosome inspector, run history. Checkpoints per island in checkpoints/evolve3/; run with SW_SCHEDULERS=8 SW_PROC_STACK=1m.
src/arena.js      the Arena's canvas renderer; src/ArenaJs.sw is generated from it (python3 scripts/embed_js.py src/arena.js ArenaJs src/ArenaJs.sw); same for src/flock.js -> src/FlockJs.sw, src/observer.js -> src/ObserverJs.sw and src/life.js -> src/LifeJs.sw and src/brain.js -> src/BrainJs.sw, src/creature.js -> src/CreatureJs.sw, src/evolve.js -> src/EvolveJs.sw
```

> **Run demos with `make run-flock` (or `scripts/run.sh <name>`), not the bare binary.** It sets `SW_SCHEDULERS=4` and ignores SIGPIPE. Status of the swarmrt issues behind that, verified against `main` @ ae943e8: [#20](https://github.com/skyblanket/swarmrt/issues/20) (SIGPIPE kills the node when a client disconnects mid-send) and [#22](https://github.com/skyblanket/swarmrt/issues/22) (mutual tail calls overflow the stack) are **fixed**, so the SIGPIPE guard only matters on older swarmrt. Still open: [#4](https://github.com/skyblanket/swarmrt/issues/4) (idle schedulers burn CPU; fix PR #76 pending), [#58](https://github.com/skyblanket/swarmrt/issues/58) (one shared ETS table scales backwards across schedulers; Flock shards its state over 16 tables) and [#57](https://github.com/skyblanket/swarmrt/issues/57) (shutdown race).

**Observer in your own app:** `import Observer` then `LiveView.start(4000, [{"/", my_view}, {"/_observer", Observer.view(%{})}])`. It only samples while someone is watching, and is read-only unless you pass `%{kill: 'true'}`.

**Build against a current swarmrt** (`make SWC=/path/to/swarmrt/bin/swc`, default `../swarmrt/bin/swc`). Older runtimes (before `ae943e8`) have a quadratic cost for tail-recursive accumulators (a 160k-element list took 83s), plus the SIGPIPE and mutual-tail-call bugs.

**What Life at Scale taught us about swarmrt** (numbers from a 16 GB M-series Mac, 4 schedulers): plain `spawn` makes 90,000 idle processes in ~0.4 s at ~10-20 KB each; a process that is actively passing messages holds ~230 KB resident, so a lively board tops out near 25k cells; message throughput is ~2.6-4M messages/s; `dyn_supervisor` silently caps at 4096 children ([swarmrt#154](https://github.com/skyblanket/swarmrt/issues/154)), so cells are spread over two alternating banks of supervisors.

**Per-view scripts:** a view map may set `js:` (a string). It is added to the page after the client and can call `window.swSend(name, value)` (-> `handle_event`) and register `window.SwEvents[name] = fn` for `{t:"ev", n:name, d:data}` frames that the server `ws_send`s. Mark client-owned elements (a canvas, a log) `sw-keep` so DOM patching leaves them alone.

## Authoring a view

A view is a map of callbacks (sw functions are first-class values):

```sw
import LiveView

fun mount(params)              { %{count: 0} }
fun render(assigns)            { LiveView.h("<div>{{}}</div>", [map_get(assigns, 'count')]) }
fun handle_event(name, _, asg) {
    if (name == "inc") { LiveView.assign(asg, 'count', map_get(asg, 'count') + 1) }
    else { asg }
}

fun main() {
    LiveView.start(4000, %{ mount: mount, render: render, handle_event: handle_event })
}
```

## Wire protocol

```
server -> client   {t:m, s:[statics], d:[dynamics]}      mount
                   {t:d, c:{idx: newval, ...}}            diff
                   {t:s, id, op, html|key}                stream op
client -> server   {t:e, n:name, v:value}                 event
                   {t:nav, p:path}                        live navigation
                   {t:join, p:path}                       initial join
                   {t:hb}                                 heartbeat
```

## Templates

Templates use `{{}}` as a positional dynamic hole. `LiveView.h(tpl, [dynamics])` splits the template on `{{}}` — that split *is* the static/dynamic seam.

```sw
LiveView.h("<b>{{}}</b> · {{}} items", [name, count])
```

## What's there

Five phases of framework: diff protocol + lifecycle (`mount`/`render`/`handle_event`/`handle_info`/`handle_post`) · components + `list` comprehension + full event bindings (`sw-click/submit/change/input/keyup/keydown/blur/focus`, debounce) + form helpers · router with `:param` routes + `sw-link` live navigation · PubSub + heartbeat + dead-session reaping · streams (`stream_append/prepend/delete/reset`) + presence (`presence_track`) + JS commands (`sw-js="toggle:#sel"`) + `connected(params)` guard + `sw-keep` morphdom escape hatch. Plus **swarmUI**: 14 components (button, card, input, label, badge, alert, separator, switch, avatar, skeleton, progress, dialog, spinner, tooltip) with a shadcn-faithful dark theme via HSL CSS variables.

## Known gaps

These need swarmrt runtime/transport changes (not framework work):

- **WS Origin / CSRF**: swarmrt's C bridge doesn't surface the `Origin` header on `ws_connect`.
- **Per-session error boundaries**: a sw panic is VM-fatal — needs catchable panics in the runtime.

v1 also flattens nested-component diffs server-side, falls back to a full re-mount on a structural template change, and ships only a basic `handle_post` upload hook (not chunked / progress).

## License

MIT.
