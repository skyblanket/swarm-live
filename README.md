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
src/liveview.sw   the framework (start/serve/session, h template, diff, PubSub, presence, streams)
src/ui.sw         swarmUI — 14 shadcn-flavoured components + UI.css() design system
src/client.sw     embedded browser client (diff protocol, morphdom, bindings, JS commands)
src/counter.sw    :4000  diff-protocol counter (the tracer bullet)
src/todo.sw       :4001  list components, sw-submit form data, live validation
src/router.sw     :4002  routes + :params + sw-link live navigation
src/chat.sw       :4003  PubSub broadcast across all sessions
src/feed.sw       :4004  stream ops + presence + a sw-js JS command
src/showcase.sw   :4005  every UI component on one live page
src/canvas.sw     :4006  shared multiplayer canvas — ink, live cursors, presence, history
src/arena.sw      :4007  Swarm Arena — 600 supervised processes on a canvas: real message comets, kills, supervisor respawns (add ?slow=8 for slow-mo)
src/flock.sw      :4008  Flock — 800 boids, each a swarmrt process; every visitor is a predator (hold to attract); live flock-order metric
src/arena.js      the Arena's canvas renderer; src/ArenaJs.sw is generated from it (python3 scripts/embed_js.py src/arena.js ArenaJs src/ArenaJs.sw); same for src/flock.js -> src/FlockJs.sw
```

> **Note:** until swarmrt fixes [skyblanket/swarmrt#20](https://github.com/skyblanket/swarmrt/issues/20), run servers as `(trap '' PIPE; ./bin/canvas)` so a client disconnecting mid-send can't kill the node.

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
