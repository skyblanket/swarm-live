module Main

# SwarmRT LiveView — todo demo (Phase 2: components, lists, forms)
#
#   bin/swc build studio/todo_lv.sw -o /tmp/todo_lv
#   /tmp/todo_lv      ->  http://localhost:4001
#
# Exercises: LiveView.list (comprehension), function components
# (todo_item), sw-submit form data, sw-change live validation,
# sw-click with sw-value-id.

import LiveView

fun mount(params) {
    %{todos: [], next_id: 1, err: ""}
}

# A function component — assigns(one todo) -> rendered struct.
fun todo_item(t) {
    id_s = to_string(map_get(t, 'id'))
    done = map_get(t, 'done')
    txt_style = if (done == 'true') { "text-decoration:line-through;opacity:.45" }
                else { "" }
    LiveView.h(
        "<li style=\"display:flex;align-items:center;gap:.5rem;padding:.45rem 0;" ++
        "border-bottom:1px solid #1e1e1e\">" ++
        "<span sw-click=\"toggle\" sw-value-id=\"" ++ id_s ++ "\" " ++
        "style=\"cursor:pointer;flex:1;" ++ txt_style ++ "\">{{}}</span>" ++
        "<button sw-click=\"del\" sw-value-id=\"" ++ id_s ++ "\" " ++
        "style=\"font-size:.78rem;padding:.2rem .6rem\">delete</button>" ++
        "</li>",
        [map_get(t, 'text')]
    )
}

fun render(assigns) {
    todos = map_get(assigns, 'todos')
    LiveView.h(
        "<div style=\"max-width:520px;margin:3rem auto;font-family:sans-serif\">" ++
        "<h1 style=\"font-size:1.6rem;font-weight:600;margin-bottom:1rem\">Todos</h1>" ++
        "<form sw-submit=\"add\" sw-change=\"validate\" style=\"display:flex;gap:.5rem\">" ++
        "<input name=\"text\" placeholder=\"what needs doing?\" autocomplete=\"off\" " ++
        "style=\"flex:1\" autofocus>" ++
        "<button type=\"submit\">add</button></form>" ++
        "<div style=\"min-height:1.2rem;margin:.4rem 0\">{{}}</div>" ++
        "<ul style=\"list-style:none;padding:0;margin:0\">{{}}</ul>" ++
        "<p style=\"color:#666;font-size:.85rem;margin-top:1rem\">{{}} item(s)</p>" ++
        "</div>",
        [ LiveView.raw(LiveView.error_tag(map_get(assigns, 'err'))),
          LiveView.list(todos, todo_item),
          length(todos) ]
    )
}

fun handle_event(name, value, assigns) {
    if (name == "add") {
        text = form_text(value)
        trimmed = string_trim(text)
        if (string_length(trimmed) == 0) {
            LiveView.assign(assigns, 'err', "can't add an empty todo")
        } else { if (string_length(text) > 60) {
            LiveView.assign(assigns, 'err', "keep it under 60 characters")
        } else {
            nid = map_get(assigns, 'next_id')
            new_todos = list_append(map_get(assigns, 'todos'),
                                    %{id: nid, text: trimmed, done: 'false'})
            a1 = LiveView.assign(assigns, 'todos', new_todos)
            a2 = LiveView.assign(a1, 'next_id', nid + 1)
            LiveView.assign(a2, 'err', "")
        }}
    }
    else { if (name == "validate") {
        over = string_length(form_text(value)) > 60
        LiveView.assign(assigns, 'err', if (over) { "keep it under 60 characters" } else { "" })
    }
    else { if (name == "toggle") {
        id_s = to_string(map_get(value, 'id'))
        LiveView.assign(assigns, 'todos', toggle_todos(map_get(assigns, 'todos'), id_s, []))
    }
    else { if (name == "del") {
        id_s = to_string(map_get(value, 'id'))
        LiveView.assign(assigns, 'todos', del_todos(map_get(assigns, 'todos'), id_s, []))
    }
    else { assigns }}}}
}

fun form_text(value) {
    if (value == nil) { "" }
    else {
        t = map_get(value, 'text')
        if (t == nil) { "" } else { to_string(t) }
    }
}

fun toggle_todos(todos, id_s, acc) {
    if (length(todos) == 0) { acc }
    else {
        t = hd(todos)
        t2 = if (to_string(map_get(t, 'id')) == id_s) {
            cur = map_get(t, 'done')
            map_put(t, 'done', if (cur == 'true') { 'false' } else { 'true' })
        } else { t }
        toggle_todos(tl(todos), id_s, list_append(acc, t2))
    }
}

fun del_todos(todos, id_s, acc) {
    if (length(todos) == 0) { acc }
    else {
        t = hd(todos)
        acc2 = if (to_string(map_get(t, 'id')) == id_s) { acc }
               else { list_append(acc, t) }
        del_todos(tl(todos), id_s, acc2)
    }
}

fun main() {
    LiveView.start(4001, %{
        title: "Todos",
        mount: mount,
        render: render,
        handle_event: handle_event
    })
}
