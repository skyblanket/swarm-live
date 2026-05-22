module Main

# SwarmRT LiveView — router demo (Phase 3: routing + live navigation)
#
#   bin/swc build studio/router_lv.sw -o /tmp/router_lv
#   /tmp/router_lv     ->  http://localhost:4002
#
# Three routes, sw-link navigation (no page reloads), and a :param
# route (/count/:start) whose param reaches mount().

import LiveView

# ---- string -> int (no builtin; small digit loop) ----
fun digit(ch) {
    if (ch == "0") { 0 } else { if (ch == "1") { 1 } else { if (ch == "2") { 2 }
    else { if (ch == "3") { 3 } else { if (ch == "4") { 4 } else { if (ch == "5") { 5 }
    else { if (ch == "6") { 6 } else { if (ch == "7") { 7 } else { if (ch == "8") { 8 }
    else { if (ch == "9") { 9 } else { 0 - 1 }}}}}}}}}}
}
fun to_i_loop(s, i, acc) {
    if (i >= string_length(s)) { acc }
    else {
        d = digit(string_sub(s, i, 1))
        if (d < 0) { acc } else { to_i_loop(s, i + 1, acc * 10 + d) }
    }
}
fun to_i(s) {
    if (s == nil) { 0 } else { to_i_loop(to_string(s), 0, 0) }
}

# ---- route: /  ----
fun home_mount(params) { %{} }
fun home_render(assigns) {
    LiveView.h(
        "<div style=\"max-width:520px;margin:4rem auto;font-family:sans-serif\">" ++
        "<h1 style=\"font-size:1.6rem;font-weight:600\">SwarmRT LiveView — Router</h1>" ++
        "<p style=\"color:#888;margin:.5rem 0 1.5rem\">live navigation, no page reloads</p>" ++
        "<p style=\"margin:.6rem 0\"><a sw-link=\"/about\" " ++
        "style=\"color:#60a5fa;cursor:pointer\">&rarr; about</a></p>" ++
        "<p style=\"margin:.6rem 0\"><a sw-link=\"/count/10\" " ++
        "style=\"color:#60a5fa;cursor:pointer\">&rarr; counter starting at 10</a></p>" ++
        "</div>",
        [])
}

# ---- route: /about ----
fun about_mount(params) { %{} }
fun about_render(assigns) {
    LiveView.h(
        "<div style=\"max-width:520px;margin:4rem auto;font-family:sans-serif\">" ++
        "<h1 style=\"font-size:1.6rem;font-weight:600\">About</h1>" ++
        "<p style=\"color:#888;margin:.5rem 0 1.5rem\">A reactive UI framework in sw, " ++
        "on the swarmrt runtime.</p>" ++
        "<p><a sw-link=\"/\" style=\"color:#60a5fa;cursor:pointer\">&larr; home</a></p>" ++
        "</div>",
        [])
}

# ---- route: /count/:start ----
fun count_mount(params) {
    %{count: to_i(map_get(params, 'start'))}
}
fun count_render(assigns) {
    LiveView.h(
        "<div style=\"max-width:520px;margin:4rem auto;font-family:sans-serif;text-align:center\">" ++
        "<h1 style=\"font-size:1.6rem;font-weight:600\">Counter</h1>" ++
        "<div style=\"font-size:5rem;font-weight:200;margin:1rem\">{{}}</div>" ++
        "<div style=\"display:flex;gap:1rem;justify-content:center;margin-bottom:1.5rem\">" ++
        "<button sw-click=\"dec\" style=\"font-size:1.3rem;padding:.5rem 1.6rem\">-</button>" ++
        "<button sw-click=\"inc\" style=\"font-size:1.3rem;padding:.5rem 1.6rem\">+</button>" ++
        "</div>" ++
        "<p><a sw-link=\"/\" style=\"color:#60a5fa;cursor:pointer\">&larr; home</a></p>" ++
        "</div>",
        [map_get(assigns, 'count')])
}
fun count_event(name, value, assigns) {
    c = map_get(assigns, 'count')
    next = if (name == "inc") { c + 1 } else { if (name == "dec") { c - 1 } else { c } }
    LiveView.assign(assigns, 'count', next)
}

fun main() {
    home    = %{title: "Home",    mount: home_mount,  render: home_render}
    about   = %{title: "About",   mount: about_mount, render: about_render}
    counter = %{title: "Counter", mount: count_mount, render: count_render,
                handle_event: count_event}
    LiveView.start(4002, [
        {"/", home},
        {"/about", about},
        {"/count/:start", counter}
    ])
}
