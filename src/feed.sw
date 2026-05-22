module Main

# SwarmRT LiveView — feed demo (Phase 5: streams, presence, JS commands)
#
#   bin/swc build studio/feed_lv.sw -o /tmp/feed_lv
#   /tmp/feed_lv      ->  http://localhost:4004
#
# Open several tabs. Posts append to the feed via STREAM ops (one DOM
# append, no list re-render). The "watching" count rides PubSub
# PRESENCE. The about panel toggles client-side via a JS COMMAND
# (sw-js) — no server round-trip.

import LiveView

fun mount(params) {
    # Only the live WS session subscribes — the dead HTTP render must
    # stay side-effect free (LiveView.connected guards that).
    if (LiveView.connected(params) == 'true') {
        LiveView.subscribe("feed")
        LiveView.presence_track("feed")
    } else {
        'noop'
    }
    %{watching: 1}
}

fun render(assigns) {
    LiveView.h(
        "<div style=\"max-width:560px;margin:3rem auto;font-family:sans-serif\">" ++
        "<h1 style=\"font-size:1.5rem;font-weight:600\">Live Feed</h1>" ++
        "<p style=\"color:#888;font-size:.85rem;margin:.3rem 0\">" ++
        "{{}} watching &middot; " ++
        "<a sw-js=\"toggle:#about\" style=\"color:#60a5fa;cursor:pointer\">about</a></p>" ++
        "<div id=\"about\" style=\"display:none;background:#161616;padding:.8rem;" ++
        "border-radius:8px;font-size:.85rem;color:#aaa;margin:.5rem 0\">" ++
        "Posts append via stream ops &mdash; no list re-render. The watcher " ++
        "count rides PubSub presence. This panel toggles client-side.</div>" ++
        "<div id=\"feed\" sw-stream style=\"min-height:220px;margin:1rem 0\"></div>" ++
        "<form sw-submit=\"post\" style=\"display:flex;gap:.5rem\">" ++
        "<input name=\"text\" placeholder=\"post to the feed...\" autocomplete=\"off\" " ++
        "style=\"flex:1\" autofocus><button type=\"submit\">post</button></form>" ++
        "</div>",
        [map_get(assigns, 'watching')])
}

# A post is broadcast to the whole room.
fun handle_event(name, value, assigns) {
    if (name == "post") {
        text = form_text(value)
        if (string_length(string_trim(text)) > 0) {
            LiveView.broadcast("feed", {'post', string_trim(text)})
        } else {
            'noop'
        }
        assigns
    } else {
        assigns
    }
}

# {'post', text}        -> append to the feed stream (no re-render)
# {'presence', _, n}    -> update the watcher count (a normal diff)
fun handle_info(msg, assigns) {
    tag = elem(msg, 0)
    if (tag == 'post') {
        LiveView.stream_append(assigns, "feed",
            "<div style=\"padding:.35rem 0;border-bottom:1px solid #1e1e1e\">" ++
            LiveView.esc(elem(msg, 1)) ++ "</div>")
        assigns
    }
    else { if (tag == 'presence') {
        LiveView.assign(assigns, 'watching', elem(msg, 2))
    }
    else {
        assigns
    }}
}

fun form_text(value) {
    if (value == nil) { "" }
    else {
        t = map_get(value, 'text')
        if (t == nil) { "" } else { to_string(t) }
    }
}

fun main() {
    LiveView.start(4004, %{
        title: "Live Feed",
        mount: mount,
        render: render,
        handle_event: handle_event,
        handle_info: handle_info
    })
}
