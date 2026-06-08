module Main

# SwarmRT LiveView — chat demo (Phase 4: PubSub, handle_info)
#
#   bin/swc build studio/chat_lv.sw -o /tmp/chat_lv
#   /tmp/chat_lv      ->  http://localhost:4003
#
# Open two browser tabs. A message sent in one is broadcast over the
# "room" topic; every subscribed session gets it in handle_info and
# re-renders. The sender sees its own message the same way — through
# the broadcast — so all tabs stay identical.

import LiveView

# mount: prompt for a username on first visit; subscribe once live.
fun mount(params) {
    if (LiveView.connected(params) == 'true') {
        LiveView.subscribe("room")
    } else {
        'noop'
    }
    %{messages: [], username: "", joined: 'false', msg_count: 0}
}

# one message row — %{user, text, n}
fun msg_item(m) {
    user = to_string(map_get(m, 'user'))
    text = to_string(map_get(m, 'text'))
    n    = to_string(map_get(m, 'n'))
    LiveView.h(
        "<div style=\"padding:.4rem 0;border-bottom:1px solid #1e1e1e;display:flex;gap:.6rem\">" ++
        "<span style=\"color:#60a5fa;font-size:.8rem;min-width:90px;flex-shrink:0\">{{}}</span>" ++
        "<span>{{}}</span>" ++
        "<span style=\"margin-left:auto;color:#444;font-size:.75rem\">#{{}}</span>" ++
        "</div>",
        [user, text, n])
}

fun render(assigns) {
    joined = map_get(assigns, 'joined')
    msgs   = map_get(assigns, 'messages')
    uname  = map_get(assigns, 'username')

    if (joined == 'false') {
        LiveView.h(
            "<div style=\"max-width:400px;margin:8rem auto;font-family:sans-serif;text-align:center\">" ++
            "<h1 style=\"font-size:1.5rem;font-weight:600;margin-bottom:1.5rem\">Live Chat</h1>" ++
            "<form sw-submit=\"join\" style=\"display:flex;flex-direction:column;gap:.75rem\">" ++
            "<input name=\"username\" placeholder=\"choose a username\" autocomplete=\"off\" autofocus " ++
            "style=\"text-align:center\">" ++
            "<button type=\"submit\" style=\"padding:.6rem\">join chat</button>" ++
            "</form></div>",
            [])
    } else {
        LiveView.h(
            "<div style=\"max-width:560px;margin:3rem auto;font-family:sans-serif\">" ++
            "<h1 style=\"font-size:1.5rem;font-weight:600\">Live Chat</h1>" ++
            "<p style=\"color:#888;margin:.4rem 0 1rem;font-size:.85rem\">" ++
            "chatting as <b>{{}}</b> &middot; open more tabs to test PubSub</p>" ++
            "<div style=\"min-height:220px;margin-bottom:1rem\">{{}}</div>" ++
            "<form sw-submit=\"say\" style=\"display:flex;gap:.5rem\">" ++
            "<input name=\"text\" placeholder=\"type a message...\" autocomplete=\"off\" " ++
            "style=\"flex:1\" autofocus><button type=\"submit\">send</button></form>" ++
            "</div>",
            [uname, LiveView.list(msgs, msg_item)])
    }
}

fun handle_event(name, value, assigns) {
    if (name == "join") {
        raw = map_get(value, 'username')
        uname = string_trim(if (raw == nil) { "" } else { to_string(raw) })
        if (string_length(uname) == 0) {
            assigns
        } else {
            a1 = LiveView.assign(assigns, 'username', uname)
            LiveView.assign(a1, 'joined', 'true')
        }
    }
    else { if (name == "say") {
        text  = string_trim(form_text(value))
        uname = map_get(assigns, 'username')
        n     = map_get(assigns, 'msg_count') + 1
        if (string_length(text) > 0) {
            LiveView.broadcast("room", {'chat', uname, text, n})
        } else {
            'noop'
        }
        assigns
    }
    else { assigns }}
}

# Cap message list at 100 to avoid unbounded growth.
fun cap_messages(msgs) {
    if (length(msgs) > 100) { tl(msgs) } else { msgs }
}

fun handle_info(msg, assigns) {
    if (elem(msg, 0) == 'chat') {
        entry = %{user: elem(msg, 1), text: elem(msg, 2), n: elem(msg, 3)}
        prev  = map_get(assigns, 'messages')
        a1 = LiveView.assign(assigns, 'messages', cap_messages(list_append(prev, entry)))
        LiveView.assign(a1, 'msg_count', elem(msg, 3))
    } else {
        assigns
    }
}

fun form_text(value) {
    if (value == nil) { "" }
    else {
        t = map_get(value, 'text')
        if (t == nil) { "" } else { to_string(t) }
    }
}

fun main() {
    LiveView.start(4003, %{
        title: "Live Chat",
        mount: mount,
        render: render,
        handle_event: handle_event,
        handle_info: handle_info
    })
}
