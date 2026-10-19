module LiveView

import Client

# ============================================================
# LiveView — server-driven reactive UI for swarmrt
# ============================================================
#
# The server holds the UI state; the browser is a thin renderer.
# Each connected tab is one sw process. After the first paint, only
# the values that *changed* cross the WebSocket — never the page.
#
# How the diff works — the static/dynamic split:
#   A `render` returns a structure, NOT a flat string:
#       %{ s: [static html segments],  d: [dynamic values] }
#   The static segments are redundancy — sent once, at mount. The
#   dynamics are the signal — re-evaluated every render and diffed;
#   only the changed ones are pushed. A counter increment costs the
#   index + the new number, not a re-rendered page.
#
# Authoring a view — a map of callbacks (plain named functions):
#   fun mount(params)               -> initial assigns map
#   fun render(assigns)             -> LiveView.h(template, [dynamics])
#   fun handle_event(name,val,asg)  -> new assigns
#   fun handle_info(msg,asg)        -> new assigns        (optional)
#   LiveView.start(4000, %{ mount: mount, render: render,
#                           handle_event: handle_event, title: "App" })
#
# Templates use {{}} as a positional hole. Splitting the template on
# {{}} *is* the static/dynamic seam — and {{}} never collides with
# CSS/JS, which only ever use single braces.
#
# Wire protocol (the embedded client is in module Client):
#   server -> client   {t:"m", s:[statics], d:[dynamic strings]}   mount
#   server -> client   {t:"d", c:{"idx":"newval", ...}}            diff
#   client -> server   {t:"e", n:"event", v:{...}}                 event

export [start, h, raw, assign, esc, page, list, input, error_tag,
        connected, subscribe, broadcast, presence_track, push_patch,
        stream_append, stream_prepend, stream_delete, stream_reset]

# ------------------------------------------------------------
# Templates
# ------------------------------------------------------------
# h(template, dynamics) -> a rendered struct %{s, d}. The static
# segments come straight out of string_split — parse once, here.
fun h(tpl, dynamics) {
    %{ s: string_split(tpl, "{{}}"), d: dynamics }
}

# Mark a string as raw, un-escaped HTML — for composed sub-renders
# (e.g. a list of rows the view built itself). Plain dynamics are
# HTML-escaped; raw ones are not.
fun raw(html) {
    %{ raw: to_string(html) }
}

# Set one key in the assigns map.
fun assign(assigns, key, val) {
    map_put(assigns, key, val)
}

# True when mount is running for a live WS session, false for the
# dead HTTP render. Guard side effects (subscribe / presence_track)
# with this so the plain GET stays pure:
#   if (LiveView.connected(params) == 'true') { LiveView.subscribe(...) }
fun connected(params) {
    if (map_get(params, '_connected') == 'true') { 'true' } else { 'false' }
}

# ------------------------------------------------------------
# Composition helpers — components, lists, forms
# ------------------------------------------------------------
# A component is just a function: assigns -> rendered struct. Embed
# one by calling it inside a dynamics list — h("<b>{{}}</b>", [card(x)])
# — stitch_dyn recurses into the nested struct. `list` is the
# comprehension helper: map item_fn over items, concatenate, return as
# raw HTML so it drops into a single {{}} hole.
fun list(items, item_fn) {
    raw(list_render(items, item_fn, ""))
}

fun list_render(items, item_fn, acc) {
    if (items == nil || length(items) == 0) { acc }
    else { list_render(tl(items), item_fn, acc ++ stitch(item_fn(hd(items)))) }
}

fun opt_or(m, k, dflt) {
    v = map_get(m, k)
    if (v == nil) { dflt } else { to_string(v) }
}

# Render an <input> with every value HTML-escaped. opts keys:
# type, name, value, placeholder, extra (raw attribute string).
fun input(opts) {
    "<input type=\"" ++ esc(opt_or(opts, 'type', "text")) ++ "\"" ++
    " name=\"" ++ esc(opt_or(opts, 'name', "")) ++ "\"" ++
    " value=\"" ++ esc(opt_or(opts, 'value', "")) ++ "\"" ++
    " placeholder=\"" ++ esc(opt_or(opts, 'placeholder', "")) ++ "\"" ++
    " autocomplete=\"off\" " ++ opt_or(opts, 'extra', "") ++ ">"
}

# Render a validation error, or "" when there is none.
fun error_tag(msg) {
    if (msg == nil || string_length(to_string(msg)) == 0) { "" }
    else { "<span style=\"color:#f87171;font-size:.8rem\">" ++ esc(msg) ++ "</span>" }
}

# ------------------------------------------------------------
# Stitching — rendered struct -> HTML string
# ------------------------------------------------------------
# Resolve one dynamic value to its HTML string:
#   nested rendered struct (%{s,d}) -> recurse
#   raw marker (%{raw})             -> verbatim
#   anything else                   -> escaped text
fun stitch_dyn(d) {
    if (d == nil) { "" }
    else { if (is_map(d) == 'false') { esc(to_string(d)) }
    else {
        nested = map_get(d, 's')
        if (nested != nil) {
            stitch(d)
        } else {
            rawv = map_get(d, 'raw')
            if (rawv != nil) { to_string(rawv) }
            else { esc(to_string(d)) }
        }
    }}
}

# Interleave statics with dynamics: s0 ++ d0 ++ s1 ++ d1 ++ ... ++ sN.
fun stitch(rendered) {
    stitch_loop(map_get(rendered, 's'), map_get(rendered, 'd'), "")
}

fun stitch_loop(statics, dyns, acc) {
    if (statics == nil || length(statics) == 0) { acc }
    else {
        acc2 = acc ++ to_string(hd(statics))
        if (dyns == nil || length(dyns) == 0) {
            stitch_loop(tl(statics), [], acc2)
        } else {
            stitch_loop(tl(statics), tl(dyns), acc2 ++ stitch_dyn(hd(dyns)))
        }
    }
}

# Resolve a list of dynamics to a list of HTML strings — this is what
# the diff compares and what the wire carries. Nested structs and raw
# markers are flattened to strings here (v1; finer per-component
# diffing is a Phase 2 refinement).
fun dyn_strings(dyns, acc) {
    if (dyns == nil || length(dyns) == 0) { acc }
    else { dyn_strings(tl(dyns), list_append(acc, stitch_dyn(hd(dyns)))) }
}

# ------------------------------------------------------------
# Diff — old dynamic strings vs new -> map of changed indices
# ------------------------------------------------------------
fun diff(old_ds, new_ds, i, acc) {
    if (new_ds == nil || length(new_ds) == 0) { acc }
    else {
        nv = hd(new_ds)
        ov = if (old_ds == nil || length(old_ds) == 0) { nil } else { hd(old_ds) }
        acc2 = if (nv == ov) { acc } else { map_put(acc, to_string(i), nv) }
        old_rest = if (old_ds == nil || length(old_ds) == 0) { [] } else { tl(old_ds) }
        diff(old_rest, tl(new_ds), i + 1, acc2)
    }
}

fun list_eq(a, b) {
    if (length(a) != length(b)) { 'false' }
    else { if (length(a) == 0) { 'true' }
    else { if (hd(a) == hd(b)) { list_eq(tl(a), tl(b)) }
    else { 'false' }}}
}

# ------------------------------------------------------------
# HTML escaping
# ------------------------------------------------------------
fun esc(s) {
    e1 = string_replace(to_string(s), "&", "&amp;")
    e2 = string_replace(e1, "<", "&lt;")
    e3 = string_replace(e2, ">", "&gt;")
    string_replace(e3, "\"", "&quot;")
}

# ------------------------------------------------------------
# Page shell — the dead-render HTML wrapper + embedded client
# ------------------------------------------------------------
fun page(title, body) {
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\">" ++
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" ++
    "<title>" ++ esc(title) ++ "</title>" ++
    "<style>*{margin:0;padding:0;box-sizing:border-box}" ++
    "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;" ++
    "background:#0a0a0a;color:#e6e6e6}" ++
    "button{cursor:pointer;border:1px solid #333;background:#1a1a1a;color:#e6e6e6;" ++
    "border-radius:8px;transition:all .15s}button:hover{background:#2a2a2a;border-color:#555}" ++
    "input,textarea,select{background:#1a1a1a;color:#e6e6e6;border:1px solid #333;" ++
    "border-radius:6px;padding:8px 12px;outline:none}</style>" ++
    "</head><body><div id=\"live-root\">" ++ body ++ "</div>" ++
    "<script>" ++ Client.js() ++ "</script></body></html>"
}

fun lv_title(view) {
    t = map_get(view, 'title')
    if (t == nil) { "SwarmRT LiveView" } else { to_string(t) }
}

fun render_view(view, assigns) {
    render_fn = map_get(view, 'render')
    render_fn(assigns)
}

# ------------------------------------------------------------
# Router + serve loop
# ------------------------------------------------------------
# start accepts a single view (%{mount,render,...}) — served at "/" —
# or a routes list ([{"/", view}, {"/u/:id", view2}, ...]).
fun start(port, arg) {
    routes = if (is_list(arg) == 'true') { arg } else { [{"/", arg}] }
    http_listen(port)
    register('lv_pubsub', spawn(pubsub_proc()))
    print("[liveview] listening on http://localhost:" ++ to_string(port))
    serve(routes)
}

# ------------------------------------------------------------
# PubSub — broadcast to every session subscribed to a topic
# ------------------------------------------------------------
# A view subscribes from mount (subscribe("room")); any process can
# broadcast("room", msg). The msg lands in each subscribed session's
# handle_info, which re-renders + diffs. One pubsub actor owns the
# topic -> pids table.
fun pubsub_proc() {
    pubsub_loop(ets_new())
}

# The actor handles both pub/sub and presence. Per topic it keeps a
# subscriber list ("sub/"++topic) and a presence-member list
# ("mem/"++topic); 'topics' lists every topic seen so {gone} can sweep
# a dead session out of all of them.
fun pubsub_loop(table) {
    receive {
        {'sub', topic, pid} ->
            reg_topic(table, topic)
            ets_put(table, "sub/" ++ topic, add_pid(ets_get(table, "sub/" ++ topic), pid))
            pubsub_loop(table)
        {'pub', topic, msg} ->
            pub_send(pids_of(table, "sub/" ++ topic), msg)
            pubsub_loop(table)
        {'track', topic, pid} ->
            reg_topic(table, topic)
            ets_put(table, "mem/" ++ topic, add_pid(ets_get(table, "mem/" ++ topic), pid))
            announce_presence(table, topic)
            pubsub_loop(table)
        {'gone', pid} ->
            purge_pid(table, pids_of(table, 'topics'), pid)
            pubsub_loop(table)
        _o ->
            pubsub_loop(table)
    }
}

fun reg_topic(table, topic) {
    ts = pids_of(table, 'topics')
    if (list_has(ts, topic) == 'true') { 'ok' }
    else { ets_put(table, 'topics', list_append(ts, topic)) }
}

fun list_has(lst, x) {
    if (length(lst) == 0) { 'false' }
    else { if (hd(lst) == x) { 'true' } else { list_has(tl(lst), x) } }
}

fun add_pid(cur, pid) {
    pids = if (cur == nil) { [] } else { cur }
    if (list_has(pids, pid) == 'true') { pids } else { list_append(pids, pid) }
}

fun pids_of(table, key) {
    cur = ets_get(table, key)
    if (cur == nil) { [] } else { cur }
}

fun remove_pid(pids, pid, acc) {
    if (length(pids) == 0) { acc }
    else {
        h = hd(pids)
        next = if (h == pid) { acc } else { list_append(acc, h) }
        remove_pid(tl(pids), pid, next)
    }
}

fun pub_send(pids, msg) {
    if (length(pids) == 0) { 'ok' }
    else {
        send(hd(pids), msg)
        pub_send(tl(pids), msg)
    }
}

# Broadcast {presence, topic, count} to a topic's subscribers.
fun announce_presence(table, topic) {
    count = length(pids_of(table, "mem/" ++ topic))
    pub_send(pids_of(table, "sub/" ++ topic), {'presence', topic, count})
}

# Sweep a dead session's pid out of every topic; re-announce presence
# for any topic it was a member of.
fun purge_pid(table, topics, pid) {
    if (length(topics) == 0) { 'ok' }
    else {
        topic = hd(topics)
        ets_put(table, "sub/" ++ topic,
                remove_pid(pids_of(table, "sub/" ++ topic), pid, []))
        was_member = list_has(pids_of(table, "mem/" ++ topic), pid)
        ets_put(table, "mem/" ++ topic,
                remove_pid(pids_of(table, "mem/" ++ topic), pid, []))
        if (was_member == 'true') { announce_presence(table, topic) } else { 'ok' }
        purge_pid(table, tl(topics), pid)
    }
}

# Subscribe the calling process (a session) to a topic.
fun subscribe(topic) {
    ps = whereis('lv_pubsub')
    if (ps == nil) { 'noop' } else { send(ps, {'sub', topic, self()}) }
}

# Broadcast a message to every session subscribed to `topic`. It
# arrives in each session's handle_info callback.
fun broadcast(topic, msg) {
    ps = whereis('lv_pubsub')
    if (ps == nil) { 'noop' } else { send(ps, {'pub', topic, msg}) }
}

# Register the calling session as present on `topic`. Every subscriber
# of that topic then receives {presence, topic, count} in handle_info.
# (Subscribe to the topic too, to actually receive that message.)
fun presence_track(topic) {
    ps = whereis('lv_pubsub')
    if (ps == nil) { 'noop' } else { send(ps, {'track', topic, self()}) }
}

# Push a URL update to the browser without remounting the view.
# Use from handle_event when the URL should reflect new state (e.g.
# /search?q=foo after a search box submission).
fun push_patch(assigns, path) {
    conn = map_get(assigns, '_conn')
    if (conn == nil) { 'noop' }
    else { ws_send(conn, json_encode(%{t: "patch", p: to_string(path)})) }
}

# A session announces its own death so presence counts stay honest.
fun notify_gone() {
    ps = whereis('lv_pubsub')
    if (ps == nil) { 'noop' } else { send(ps, {'gone', self()}) }
}

# ------------------------------------------------------------
# Streams — imperative item ops for append-heavy UIs (feeds, logs,
# chat). A stream container is <div id="X" sw-stream>; these push one
# DOM op instead of re-diffing the whole list. The framework injects
# the connection into assigns as '_conn', so views call these with
# assigns. Items carry sw-key="..." to be stream_delete-able.
# ------------------------------------------------------------
fun stream_append(assigns, id, html) {
    stream_op(assigns, %{t: "s", id: to_string(id), op: "append", html: to_string(html)})
}
fun stream_prepend(assigns, id, html) {
    stream_op(assigns, %{t: "s", id: to_string(id), op: "prepend", html: to_string(html)})
}
fun stream_delete(assigns, id, key) {
    stream_op(assigns, %{t: "s", id: to_string(id), op: "delete", key: to_string(key)})
}
fun stream_reset(assigns, id) {
    stream_op(assigns, %{t: "s", id: to_string(id), op: "reset"})
}
fun stream_op(assigns, msg) {
    conn = map_get(assigns, '_conn')
    if (conn == nil) { 'noop' } else { ws_send(conn, json_encode(msg)) }
}

# Match `path` against the routes list. Literal segments must match;
# a `:name` segment captures into params. -> %{view, params} | nil.
fun match_route(routes, path) {
    if (length(routes) == 0) { nil }
    else {
        entry = hd(routes)
        params = try_match(to_string(elem(entry, 0)), path, map_new())
        if (params == nil) { match_route(tl(routes), path) }
        else { %{view: elem(entry, 1), params: params} }
    }
}

fun try_match(route, path, params) {
    r_segs = string_split(route, "/")
    p_segs = string_split(path, "/")
    if (length(r_segs) != length(p_segs)) { nil }
    else { match_segs(r_segs, p_segs, params) }
}

fun match_segs(rs, ps, params) {
    if (length(rs) == 0) { params }
    else {
        r = hd(rs)
        if (string_length(r) > 0 && string_sub(r, 0, 1) == ":") {
            key = string_sub(r, 1, string_length(r) - 1)
            match_segs(tl(rs), tl(ps), map_put(params, key, hd(ps)))
        }
        else { if (r == hd(ps)) { match_segs(tl(rs), tl(ps), params) }
        else { nil }}
    }
}

fun notfound_body() {
    "<div style=\"text-align:center;padding:5rem;font-family:sans-serif\">" ++
    "<h1 style=\"font-size:3rem;font-weight:200\">404</h1>" ++
    "<p style=\"color:#888\">no route here</p></div>"
}

# The accept loop. A plain GET gets the server-rendered "dead" page
# for the matched route (instant first paint, works with JS off / for
# crawlers); the page's embedded client upgrades to /live/ws and tells
# the session which path it is on.
fun serve(routes) {
    receive {
        {'http_request', conn, 'GET', "/favicon.ico", _h, _b} ->
            http_respond(conn, 204, "", "")
            serve(routes)

        {'http_request', conn, 'GET', path, _h, _b} ->
            matched = match_route(routes, path)
            if (matched == nil) {
                http_respond(conn, 404, "Content-Type: text/html\r\n",
                             page("Not Found", notfound_body()))
            } else {
                v = map_get(matched, 'view')
                mfn = map_get(v, 'mount')
                # dead render — _connected:false so views skip subscribe /
                # presence side effects on the plain GET.
                dr = mfn(map_put(map_get(matched, 'params'), '_connected', 'false'))
                http_respond(conn, 200, "Content-Type: text/html\r\n",
                             page(lv_title(v), stitch(render_view(v, dr))))
            }
            serve(routes)

        {'ws_connect', conn, "/live/ws"} ->
            pid = spawn(session(conn, routes))
            ws_set_handler(conn, pid)
            serve(routes)

        {'http_request', conn, 'POST', path, _h, body} ->
            matched = match_route(routes, path)
            resp = if (matched == nil) { "no route" }
                   else {
                       hp = map_get(map_get(matched, 'view'), 'handle_post')
                       if (hp == nil) { "ok" } else { to_string(hp(path, body)) }
                   }
            http_respond(conn, 200, "Content-Type: text/plain\r\n", resp)
            serve(routes)

        _other ->
            serve(routes)
    }
}

# ------------------------------------------------------------
# session — one process per connected tab
# ------------------------------------------------------------
# The browser opens /live/ws and immediately sends {t:"join", p:path}
# so the session knows which route to mount.
fun session(conn, routes) {
    receive {
        {'ws_message', _c, raw_msg} ->
            msg = json_decode(raw_msg)
            path = if (msg == nil) { "/" }
                   else {
                       p = map_get(msg, 'p')
                       if (p == nil) { "/" } else { to_string(p) }
                   }
            navigate(conn, routes, path)
        {'ws_close', _c} ->
            'ok'
        _o ->
            session(conn, routes)
    }
}

# Mount the view for `path` and push a fresh {t:"m"} — used for the
# initial join and for every live navigation.
fun navigate(conn, routes, path) {
    matched = match_route(routes, path)
    if (matched == nil) {
        ws_send(conn, json_encode(%{t: "m", s: [notfound_body()], d: []}))
        notfound_loop(conn, routes)
    } else {
        view = map_get(matched, 'view')
        mount_fn = map_get(view, 'mount')
        # Live session mount: _connected:true (side effects run), and
        # the connection injected as '_conn' so views can reach the
        # socket for stream ops without a wider callback signature.
        mp = map_put(map_get(matched, 'params'), '_connected', 'true')
        assigns = map_put(mount_fn(mp), '_conn', conn)
        rendered = render_view(view, assigns)
        statics = map_get(rendered, 's')
        dstrings = dyn_strings(map_get(rendered, 'd'), [])
        ws_send(conn, json_encode(%{t: "m", s: statics, d: dstrings}))
        session_loop(conn, routes, view, assigns, statics, dstrings)
    }
}

# A 404 is still a live session — keep listening so the user can
# navigate away with a sw-link.
fun notfound_loop(conn, routes) {
    receive {
        {'ws_message', _c, raw_msg} ->
            msg = json_decode(raw_msg)
            if (msg != nil && map_get(msg, 't') == "nav") {
                navigate(conn, routes, to_string(map_get(msg, 'p')))
            } else {
                notfound_loop(conn, routes)
            }
        {'ws_close', _c} -> 'ok'
        _o -> notfound_loop(conn, routes)
    }
}

fun session_loop(conn, routes, view, assigns, last_s, last_d) {
    receive {
        {'ws_message', _c, raw_msg} ->
            msg = json_decode(raw_msg)
            kind = if (msg == nil) { nil } else { map_get(msg, 't') }
            if (msg == nil || kind == "hb") {
                # heartbeat ping — just resets the idle timer below
                session_loop(conn, routes, view, assigns, last_s, last_d)
            } else { if (kind == "nav") {
                navigate(conn, routes, to_string(map_get(msg, 'p')))
            } else {
                he = map_get(view, 'handle_event')
                new_assigns = if (he == nil) { assigns }
                              else { he(map_get(msg, 'n'), map_get(msg, 'v'), assigns) }
                st = push_update(conn, view, new_assigns, last_s, last_d)
                session_loop(conn, routes, view, new_assigns, elem(st, 0), elem(st, 1))
            }}

        {'ws_close', _c} ->
            notify_gone()
            'ok'

        other ->
            hi = map_get(view, 'handle_info')
            if (hi == nil) {
                session_loop(conn, routes, view, assigns, last_s, last_d)
            } else {
                new_assigns = hi(other, assigns)
                st = push_update(conn, view, new_assigns, last_s, last_d)
                session_loop(conn, routes, view, new_assigns, elem(st, 0), elem(st, 1))
            }

        after 90000 {
            # No frame (not even a heartbeat) in 90s — the client is a
            # half-open ghost. Drop the connection and let the session end.
            notify_gone()
            ws_close(conn)
            'ok'
        }
    }
}

# Re-render against new assigns. If the static structure is unchanged
# (the common case), push only the changed dynamics. If the structure
# itself changed (a conditional flipped, a list grew), fall back to a
# fresh mount — correct, just less frugal; Phase 2 makes structural
# change incremental too.
#
# Returns {statics, dstrings} for the caller to loop with. It must NOT
# call session_loop itself: mutual tail calls aren't TCO'd, so every
# event would grow the stack until it overflowed (high-rate events like
# pointer moves hit that within seconds). session_loop self-tail-calls.
fun push_update(conn, view, assigns, last_s, last_d) {
    rendered = render_view(view, assigns)
    statics = map_get(rendered, 's')
    dstrings = dyn_strings(map_get(rendered, 'd'), [])
    if (list_eq(statics, last_s) == 'false') {
        ws_send(conn, json_encode(%{t: "m", s: statics, d: dstrings}))
    } else {
        changes = diff(last_d, dstrings, 0, map_new())
        if (length(map_keys(changes)) > 0) {
            ws_send(conn, json_encode(%{t: "d", c: changes}))
        } else {
            'noop'
        }
    }
    {statics, dstrings}
}
