module Main

# swarm-live — shared multiplayer canvas
#
#   make bin/canvas && ./bin/canvas      ->  http://localhost:4006
#
# Open several tabs. Drawing, live cursors and presence — no client
# framework. Ink is broadcast over PubSub and painted by the client's
# sw-canvas hook; remote cursors are upserted into an sw-ttl container
# so they vanish when a peer goes quiet. A "board" process keeps the
# stroke history so late joiners see what is already on the wall.

import LiveView
import Std

let palette = ["#f87171", "#fb923c", "#facc15", "#4ade80", "#22d3ee", "#60a5fa", "#a78bfa", "#f472b6"]
let max_segs = 40000
let keep_segs = 30000

# ------------------------------------------------------------
# Board — owns the stroke history (newest first)
# ------------------------------------------------------------
fun board_loop(segs, n) {
    receive {
        {'seg', s} ->
            if (n >= max_segs) {
                board_loop(list_prepend_one(Std.take(segs, keep_segs), s), keep_segs + 1)
            } else {
                board_loop(list_prepend_one(segs, s), n + 1)
            }
        {'clear'} ->
            board_loop([], 0)
        {'hist', pid} ->
            send(pid, {'history', Std.reverse(segs)})
            board_loop(segs, n)
        _o ->
            board_loop(segs, n)
    }
}

fun list_prepend_one(lst, x) { [x | lst] }

fun board_send(msg) {
    b = whereis('canvas_board')
    if (b == nil) { 'noop' } else { send(b, msg) }
}

# ------------------------------------------------------------
# View
# ------------------------------------------------------------
fun pick(lst, i) {
    if (i <= 0) { hd(lst) } else { pick(tl(lst), i - 1) }
}

fun mount(params) {
    id = uuid()
    color = pick(palette, ord(id) % length(palette))
    name = "guest-" ++ string_sub(id, 0, 4)
    if (LiveView.connected(params) == 'true') {
        LiveView.subscribe("canvas")
        LiveView.presence_track("canvas")
        board_send({'hist', self()})
    } else {
        'noop'
    }
    %{id: id, color: color, name: name, last: nil, watching: 1}
}

fun render(assigns) {
    LiveView.h(
        "<div style=\"position:fixed;inset:0;background:#0a0a0a;color:#e6e6e6;" ++
        "font-family:sans-serif;display:flex;flex-direction:column\">" ++
        "<div style=\"height:48px;display:flex;align-items:center;gap:1rem;padding:0 1rem;" ++
        "border-bottom:1px solid #1e1e1e;font-size:.85rem;flex-shrink:0\">" ++
        "<b style=\"font-size:1rem\">swarm canvas</b>" ++
        "<span style=\"color:#888\">{{}} here</span>" ++
        "<span style=\"display:flex;align-items:center;gap:.4rem\">" ++
        "<i style=\"width:10px;height:10px;border-radius:50%;background:{{}}\"></i>{{}}</span>" ++
        "<button sw-click=\"clear\" style=\"margin-left:auto\">clear</button></div>" ++
        "<div style=\"flex:1;display:flex;align-items:center;justify-content:center;min-height:0\">" ++
        "<div id=\"board\" sw-pointer=\"ptr\" style=\"position:relative;" ++
        "width:min(100vw,calc((100vh - 48px) * 16 / 9));aspect-ratio:16/9;" ++
        "background:#111;touch-action:none;cursor:crosshair;overflow:hidden\">" ++
        "<div id=\"ink\" sw-stream sw-canvas style=\"position:absolute;inset:0\"></div>" ++
        "<div id=\"cursors\" sw-stream sw-ttl=\"4000\" " ++
        "style=\"position:absolute;inset:0;pointer-events:none;overflow:hidden\"></div>" ++
        "</div></div></div>",
        [map_get(assigns, 'watching'),
         map_get(assigns, 'color'),
         LiveView.esc(map_get(assigns, 'name'))])
}

fun ev_num(value, key) {
    v = if (value == nil) { 0 } else { map_get(value, key) }
    if (v == nil) { 0 } else { v }
}

# Pointer events become segments (from last point to this one) plus a
# cursor update. 'down' starts a stroke; 'draw' extends it; 'up' ends it.
fun handle_event(name, value, assigns) {
    if (name == "clear") {
        board_send({'clear'})
        LiveView.broadcast("canvas", {'clear'})
        assigns
    } else { if (name == "ptr") {
        k = if (value == nil) { "" } else { to_string(map_get(value, 'k')) }
        x = ev_num(value, 'x')
        y = ev_num(value, 'y')
        id = map_get(assigns, 'id')
        color = map_get(assigns, 'color')
        last = map_get(assigns, 'last')
        LiveView.broadcast("canvas", {'cursor', id, map_get(assigns, 'name'), color, x, y})
        if (k == "down") {
            LiveView.assign(assigns, 'last', [x, y])
        } else { if (k == "draw" || k == "up") {
            if (last == nil) { assigns }
            else {
                seg = [hd(last), hd(tl(last)), x, y, color]
                board_send({'seg', seg})
                LiveView.broadcast("canvas", {'seg', seg})
                if (k == "up") { LiveView.assign(assigns, 'last', nil) }
                else { LiveView.assign(assigns, 'last', [x, y]) }
            }
        } else {
            assigns
        }}
    } else {
        assigns
    }}
}

fun cursor_html(id, name, color, x, y) {
    "<div sw-key=\"" ++ id ++ "\" style=\"position:absolute;pointer-events:none;" ++
    "left:" ++ to_string(x * 100) ++ "%;top:" ++ to_string(y * 100) ++ "%\">" ++
    "<svg width=\"16\" height=\"16\" viewBox=\"0 0 16 16\"><path d=\"M1 1 L1 13 L5 10 L8 15 L10 14 L7 9 L12 9 Z\" fill=\"" ++
    color ++ "\" stroke=\"#000\" stroke-width=\"1\"/></svg>" ++
    "<span style=\"position:absolute;left:14px;top:12px;white-space:nowrap;font-size:11px;" ++
    "background:" ++ color ++ ";color:#000;padding:1px 6px;border-radius:9999px\">" ++
    LiveView.esc(name) ++ "</span></div>"
}

fun handle_info(msg, assigns) {
    tag = elem(msg, 0)
    if (tag == 'seg') {
        LiveView.stream_op(assigns, %{t: "s", id: "ink", op: "draw", segs: [elem(msg, 1)]})
        assigns
    } else { if (tag == 'history') {
        LiveView.stream_op(assigns, %{t: "s", id: "ink", op: "draw", segs: elem(msg, 1)})
        assigns
    } else { if (tag == 'clear') {
        LiveView.stream_op(assigns, %{t: "s", id: "ink", op: "reset"})
        assigns
    } else { if (tag == 'cursor') {
        if (elem(msg, 1) == map_get(assigns, 'id')) { assigns }
        else {
            LiveView.stream_op(assigns, %{t: "s", id: "cursors", op: "upsert",
                key: elem(msg, 1),
                html: cursor_html(elem(msg, 1), elem(msg, 2), elem(msg, 3), elem(msg, 4), elem(msg, 5))})
            assigns
        }
    } else { if (tag == 'presence') {
        LiveView.assign(assigns, 'watching', elem(msg, 2))
    } else {
        assigns
    }}}}}
}

fun main() {
    register('canvas_board', spawn(board_loop([], 0)))
    LiveView.start(4006, %{
        title: "swarm canvas",
        mount: mount,
        render: render,
        handle_event: handle_event,
        handle_info: handle_info
    })
}
