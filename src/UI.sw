module UI

# ============================================================
# swarmUI — a shadcn-flavoured component kit for swarmrt LiveView
# ============================================================
#
# Every component is a plain function that returns an HTML string,
# styled with the design-system classes from UI.css(). Because the
# LiveView template engine splits the *final* string on {{}}, a
# component may contain {{}} holes and they compose straight into the
# enclosing view — so dynamic content drops in naturally:
#
#   import UI
#   fun render(assigns) {
#     LiveView.h(
#       UI.css() ++
#       UI.card(%{ title: "Score", content: "<b>{{}}</b>" }),
#       [map_get(assigns, 'score')])
#   }
#
# Buttons wire to LiveView events with `event:` (-> sw-click) or run a
# client-side command with `js:` (-> sw-js). Dark theme, shadcn tokens.

import LiveView

export [css, button, card, input, label, badge, alert, separator,
        switch, avatar, skeleton, progress, dialog, spinner, tooltip,
        select, textarea, table, tabs]

# opt-or-default, stringified.
fun o(opts, k, dflt) {
    v = map_get(opts, k)
    if (v == nil) { dflt } else { to_string(v) }
}

# ------------------------------------------------------------
# css — the design system. Drop UI.css() once at the top of a view.
# ------------------------------------------------------------
fun css() {
    "<style>" ++
    ":root{" ++
    "--bg:240 10% 3.9%;--fg:0 0% 98%;--card:240 10% 5.1%;" ++
    "--muted:240 3.7% 15.9%;--muted-fg:240 5% 64.9%;" ++
    "--primary:0 0% 98%;--primary-fg:240 5.9% 10%;" ++
    "--secondary:240 3.7% 15.9%;--secondary-fg:0 0% 98%;" ++
    "--destructive:0 72% 51%;--destructive-fg:0 0% 98%;" ++
    "--border:240 3.7% 15.9%;--ring:240 4.9% 83.9%;--radius:.5rem}" ++
    "*{box-sizing:border-box}" ++
    "body{background:hsl(var(--bg));color:hsl(var(--fg));" ++
    "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;" ++
    "-webkit-font-smoothing:antialiased}" ++
    ".ui-btn{display:inline-flex;align-items:center;justify-content:center;gap:.5rem;" ++
    "height:2.5rem;padding:0 1rem;border-radius:var(--radius);font-size:.875rem;" ++
    "font-weight:500;border:1px solid transparent;cursor:pointer;transition:.15s;" ++
    "white-space:nowrap;font-family:inherit}" ++
    ".ui-btn:focus-visible{outline:2px solid hsl(var(--ring));outline-offset:2px}" ++
    ".ui-btn:active{transform:translateY(1px)}" ++
    ".ui-btn-default{background:hsl(var(--primary));color:hsl(var(--primary-fg))}" ++
    ".ui-btn-default:hover{opacity:.9}" ++
    ".ui-btn-secondary{background:hsl(var(--secondary));color:hsl(var(--secondary-fg))}" ++
    ".ui-btn-secondary:hover{background:hsl(var(--muted))}" ++
    ".ui-btn-destructive{background:hsl(var(--destructive));color:hsl(var(--destructive-fg))}" ++
    ".ui-btn-destructive:hover{opacity:.9}" ++
    ".ui-btn-outline{border-color:hsl(var(--border));background:transparent;color:hsl(var(--fg))}" ++
    ".ui-btn-outline:hover{background:hsl(var(--muted))}" ++
    ".ui-btn-ghost{background:transparent;color:hsl(var(--fg))}" ++
    ".ui-btn-ghost:hover{background:hsl(var(--muted))}" ++
    ".ui-btn-link{background:transparent;color:hsl(var(--fg));text-decoration:underline}" ++
    ".ui-btn-sm{height:2.25rem;padding:0 .75rem;font-size:.8rem}" ++
    ".ui-btn-lg{height:2.75rem;padding:0 2rem}" ++
    ".ui-card{background:hsl(var(--card));border:1px solid hsl(var(--border));" ++
    "border-radius:var(--radius)}" ++
    ".ui-card-header{padding:1.5rem 1.5rem .5rem}" ++
    ".ui-card-title{font-size:1.05rem;font-weight:600;letter-spacing:-.01em}" ++
    ".ui-card-desc{font-size:.85rem;color:hsl(var(--muted-fg));margin-top:.3rem}" ++
    ".ui-card-content{padding:1rem 1.5rem 1.5rem}" ++
    ".ui-card-footer{padding:0 1.5rem 1.5rem;display:flex;gap:.5rem}" ++
    ".ui-input{display:block;width:100%;height:2.5rem;border-radius:var(--radius);" ++
    "border:1px solid hsl(var(--border));background:transparent;padding:0 .75rem;" ++
    "font-size:.875rem;color:hsl(var(--fg));font-family:inherit}" ++
    ".ui-input:focus{outline:none;border-color:hsl(var(--ring))}" ++
    ".ui-input::placeholder{color:hsl(var(--muted-fg))}" ++
    ".ui-label{font-size:.875rem;font-weight:500;display:block;margin-bottom:.4rem}" ++
    ".ui-badge{display:inline-flex;align-items:center;border-radius:9999px;" ++
    "padding:.18rem .6rem;font-size:.72rem;font-weight:600;border:1px solid transparent}" ++
    ".ui-badge-default{background:hsl(var(--primary));color:hsl(var(--primary-fg))}" ++
    ".ui-badge-secondary{background:hsl(var(--secondary));color:hsl(var(--secondary-fg))}" ++
    ".ui-badge-destructive{background:hsl(var(--destructive));color:hsl(var(--destructive-fg))}" ++
    ".ui-badge-outline{border-color:hsl(var(--border));color:hsl(var(--fg))}" ++
    ".ui-alert{border:1px solid hsl(var(--border));border-radius:var(--radius);" ++
    "padding:1rem 1.1rem;background:hsl(var(--card))}" ++
    ".ui-alert-destructive{border-color:hsl(var(--destructive) / .5)}" ++
    ".ui-alert-destructive .ui-alert-title{color:hsl(var(--destructive))}" ++
    ".ui-alert-title{font-weight:600;font-size:.9rem;margin-bottom:.2rem}" ++
    ".ui-alert-desc{font-size:.85rem;color:hsl(var(--muted-fg))}" ++
    ".ui-sep{height:1px;background:hsl(var(--border));border:0;margin:1.25rem 0}" ++
    ".ui-switch{position:relative;display:inline-flex;width:2.6rem;height:1.45rem;" ++
    "vertical-align:middle}" ++
    ".ui-switch-track{position:absolute;inset:0;background:hsl(var(--muted));" ++
    "border-radius:9999px;cursor:pointer;transition:.15s}" ++
    ".ui-switch-track:before{content:'';position:absolute;height:1.1rem;width:1.1rem;" ++
    "left:.17rem;top:.17rem;background:hsl(var(--fg));border-radius:9999px;transition:.15s}" ++
    ".ui-switch-on .ui-switch-track{background:hsl(var(--primary))}" ++
    ".ui-switch-on .ui-switch-track:before{transform:translateX(1.15rem);" ++
    "background:hsl(var(--primary-fg))}" ++
    ".ui-avatar{width:2.5rem;height:2.5rem;border-radius:9999px;background:hsl(var(--muted));" ++
    "display:inline-flex;align-items:center;justify-content:center;font-size:.8rem;" ++
    "font-weight:600;color:hsl(var(--fg))}" ++
    ".ui-skeleton{background:hsl(var(--muted));border-radius:var(--radius);" ++
    "animation:ui-pulse 1.6s ease-in-out infinite}" ++
    "@keyframes ui-pulse{50%{opacity:.45}}" ++
    ".ui-progress{height:.55rem;background:hsl(var(--muted));border-radius:9999px;" ++
    "overflow:hidden}" ++
    ".ui-progress-bar{height:100%;background:hsl(var(--primary));border-radius:9999px;" ++
    "transition:width .3s}" ++
    ".ui-dialog-overlay{position:fixed;inset:0;background:rgba(0,0,0,.72);" ++
    "display:flex;align-items:center;justify-content:center;z-index:50;padding:1rem}" ++
    ".ui-dialog{background:hsl(var(--card));border:1px solid hsl(var(--border));" ++
    "border-radius:var(--radius);padding:1.5rem;max-width:28rem;width:100%}" ++
    ".ui-spinner{display:inline-block;width:1.2rem;height:1.2rem;" ++
    "border:2px solid hsl(var(--muted));border-top-color:hsl(var(--fg));" ++
    "border-radius:9999px;animation:ui-spin .6s linear infinite}" ++
    "@keyframes ui-spin{to{transform:rotate(360deg)}}" ++
    ".ui-tooltip{position:relative;display:inline-block}" ++
    ".ui-tooltip-text{visibility:hidden;opacity:0;position:absolute;bottom:135%;" ++
    "left:50%;transform:translateX(-50%);background:hsl(var(--fg));" ++
    "color:hsl(var(--bg));padding:.25rem .55rem;border-radius:.35rem;" ++
    "font-size:.72rem;white-space:nowrap;transition:opacity .12s}" ++
    ".ui-tooltip:hover .ui-tooltip-text{visibility:visible;opacity:1}" ++
    ".ui-tabs{display:flex;gap:.25rem;border-bottom:1px solid hsl(var(--border));margin-bottom:1rem}" ++
    ".ui-tab{background:transparent;border:none;color:hsl(var(--muted-fg));padding:.55rem .9rem;" ++
    "font-size:.875rem;font-weight:500;cursor:pointer;border-bottom:2px solid transparent;" ++
    "margin-bottom:-1px;border-radius:0;transition:.12s;font-family:inherit}" ++
    ".ui-tab:hover{color:hsl(var(--fg))}" ++
    ".ui-tab-active{color:hsl(var(--fg));border-bottom-color:hsl(var(--primary))}" ++
    ".ui-tab-panel{}" ++
    ".ui-table{width:100%;border-collapse:collapse;font-size:.875rem}" ++
    ".ui-table th{text-align:left;padding:.6rem .85rem;font-weight:600;" ++
    "border-bottom:2px solid hsl(var(--border));color:hsl(var(--muted-fg))}" ++
    ".ui-table td{padding:.55rem .85rem;border-bottom:1px solid hsl(var(--border))}" ++
    ".ui-table tbody tr:hover{background:hsl(var(--muted) / .4)}" ++
    "</style>"
}

# ------------------------------------------------------------
# Components
# ------------------------------------------------------------
# button — %{label, variant?, size?, event?, js?, type?}
#   variant: default | secondary | destructive | outline | ghost | link
#   event -> sw-click (LiveView event)   js -> sw-js (client command)
fun button(opts) {
    size = o(opts, 'size', "")
    sz = if (size == "") { "" } else { " ui-btn-" ++ size }
    ev = o(opts, 'event', "")
    cl = if (ev == "") { "" } else { " sw-click=\"" ++ ev ++ "\"" }
    j = o(opts, 'js', "")
    js = if (j == "") { "" } else { " sw-js=\"" ++ j ++ "\"" }
    "<button type=\"" ++ o(opts, 'type', "button") ++ "\" class=\"ui-btn ui-btn-" ++
    o(opts, 'variant', "default") ++ sz ++ "\"" ++ cl ++ js ++ ">" ++
    LiveView.esc(o(opts, 'label', "")) ++ "</button>"
}

# card — %{title?, description?, content, footer?}
# content and footer are raw HTML (compose other components); title and
# description are escaped text.
fun card(opts) {
    title = o(opts, 'title', "")
    desc = o(opts, 'description', "")
    header = if (title == "" && desc == "") { "" }
             else {
                 t = if (title == "") { "" }
                     else { "<div class=\"ui-card-title\">" ++ LiveView.esc(title) ++ "</div>" }
                 d = if (desc == "") { "" }
                     else { "<div class=\"ui-card-desc\">" ++ LiveView.esc(desc) ++ "</div>" }
                 "<div class=\"ui-card-header\">" ++ t ++ d ++ "</div>"
             }
    footer = o(opts, 'footer', "")
    foot = if (footer == "") { "" }
           else { "<div class=\"ui-card-footer\">" ++ footer ++ "</div>" }
    "<div class=\"ui-card\">" ++ header ++
    "<div class=\"ui-card-content\">" ++ o(opts, 'content', "") ++ "</div>" ++
    foot ++ "</div>"
}

# input — %{name, type?, value?, placeholder?, event?, extra?}
# event -> sw-input (live keystrokes).
fun input(opts) {
    ev = o(opts, 'event', "")
    cl = if (ev == "") { "" } else { " sw-input=\"" ++ ev ++ "\"" }
    "<input class=\"ui-input\" type=\"" ++ o(opts, 'type', "text") ++ "\"" ++
    " name=\"" ++ LiveView.esc(o(opts, 'name', "")) ++ "\"" ++
    " value=\"" ++ LiveView.esc(o(opts, 'value', "")) ++ "\"" ++
    " placeholder=\"" ++ LiveView.esc(o(opts, 'placeholder', "")) ++ "\"" ++
    " autocomplete=\"off\"" ++ cl ++ " " ++ o(opts, 'extra', "") ++ ">"
}

fun label(text) {
    "<label class=\"ui-label\">" ++ LiveView.esc(text) ++ "</label>"
}

# badge — %{label, variant?}  variant: default|secondary|destructive|outline
fun badge(opts) {
    "<span class=\"ui-badge ui-badge-" ++ o(opts, 'variant', "default") ++ "\">" ++
    LiveView.esc(o(opts, 'label', "")) ++ "</span>"
}

# alert — %{title?, body, variant?}  variant: default|destructive
fun alert(opts) {
    variant = o(opts, 'variant', "default")
    vc = if (variant == "destructive") { " ui-alert-destructive" } else { "" }
    title = o(opts, 'title', "")
    t = if (title == "") { "" }
        else { "<div class=\"ui-alert-title\">" ++ LiveView.esc(title) ++ "</div>" }
    "<div class=\"ui-alert" ++ vc ++ "\">" ++ t ++
    "<div class=\"ui-alert-desc\">" ++ LiveView.esc(o(opts, 'body', "")) ++ "</div></div>"
}

fun separator() {
    "<hr class=\"ui-sep\">"
}

# switch — %{event?, on?}  on:"true" draws the toggled state. Server-
# driven: clicking fires `event`; the view flips state and re-renders.
fun switch(opts) {
    ev = o(opts, 'event', "")
    cl = if (ev == "") { "" } else { " sw-click=\"" ++ ev ++ "\"" }
    on = if (o(opts, 'on', "false") == "true") { " ui-switch-on" } else { "" }
    "<span class=\"ui-switch" ++ on ++ "\"" ++ cl ++
    "><span class=\"ui-switch-track\"></span></span>"
}

# avatar — %{text}  draws initials (first 2 chars).
fun avatar(opts) {
    t = o(opts, 'text', "?")
    initials = if (string_length(t) > 2) { string_sub(t, 0, 2) } else { t }
    "<span class=\"ui-avatar\">" ++ LiveView.esc(initials) ++ "</span>"
}

# skeleton — %{w?, h?}  loading placeholder; w/h are CSS lengths.
fun skeleton(opts) {
    "<div class=\"ui-skeleton\" style=\"width:" ++ o(opts, 'w', "100%") ++
    ";height:" ++ o(opts, 'h', "1rem") ++ "\"></div>"
}

# progress — %{value}  0..100
fun progress(opts) {
    "<div class=\"ui-progress\"><div class=\"ui-progress-bar\" style=\"width:" ++
    o(opts, 'value', "0") ++ "%\"></div></div>"
}

# dialog — %{id, title?, body, footer?}  Hidden until a trigger runs
# js:"show:#<id>"; close with js:"hide:#<id>".
fun dialog(opts) {
    id = o(opts, 'id', "dialog")
    title = o(opts, 'title', "")
    t = if (title == "") { "" }
        else { "<div class=\"ui-card-title\" style=\"margin-bottom:.5rem\">" ++
               LiveView.esc(title) ++ "</div>" }
    footer = o(opts, 'footer', "")
    foot = if (footer == "") { "" }
           else { "<div style=\"display:flex;gap:.5rem;justify-content:flex-end;" ++
                  "margin-top:1.25rem\">" ++ footer ++ "</div>" }
    "<div id=\"" ++ id ++ "\" sw-keep class=\"ui-dialog-overlay\" style=\"display:none\">" ++
    "<div class=\"ui-dialog\">" ++ t ++
    "<div style=\"font-size:.875rem;color:hsl(var(--muted-fg))\">" ++
    o(opts, 'body', "") ++ "</div>" ++ foot ++ "</div></div>"
}

fun spinner() {
    "<span class=\"ui-spinner\"></span>"
}

# tooltip — %{label, tip}
fun tooltip(opts) {
    "<span class=\"ui-tooltip\">" ++ LiveView.esc(o(opts, 'label', "")) ++
    "<span class=\"ui-tooltip-text\">" ++ LiveView.esc(o(opts, 'tip', "")) ++
    "</span></span>"
}

# select — %{name, options, value?, event?, extra?}
# options: list of %{value, label} maps. Server-driven via sw-change.
fun select(opts) {
    ev = o(opts, 'event', "")
    cl = if (ev == "") { "" } else { " sw-change=\"" ++ ev ++ "\"" }
    cur = o(opts, 'value', "")
    items = map_get(opts, 'options')
    body = if (items == nil) { "" } else { select_opts(items, cur, "") }
    "<select class=\"ui-input\" name=\"" ++ LiveView.esc(o(opts, 'name', "")) ++ "\"" ++
    cl ++ " " ++ o(opts, 'extra', "") ++ ">" ++ body ++ "</select>"
}

fun select_opts(items, cur, acc) {
    if (items == nil || length(items) == 0) { acc }
    else {
        it = hd(items)
        v  = to_string(map_get(it, 'value'))
        lbl = to_string(map_get(it, 'label'))
        sel = if (v == cur) { " selected" } else { "" }
        opt = "<option value=\"" ++ LiveView.esc(v) ++ "\"" ++ sel ++ ">" ++
              LiveView.esc(lbl) ++ "</option>"
        select_opts(tl(items), cur, acc ++ opt)
    }
}

# textarea — %{name, value?, placeholder?, rows?, event?, extra?}
fun textarea(opts) {
    ev = o(opts, 'event', "")
    cl = if (ev == "") { "" } else { " sw-input=\"" ++ ev ++ "\"" }
    "<textarea class=\"ui-input\" name=\"" ++ LiveView.esc(o(opts, 'name', "")) ++ "\"" ++
    " rows=\"" ++ o(opts, 'rows', "3") ++ "\"" ++
    " placeholder=\"" ++ LiveView.esc(o(opts, 'placeholder', "")) ++ "\"" ++
    " style=\"height:auto;padding:.5rem .75rem;resize:vertical\"" ++
    cl ++ " " ++ o(opts, 'extra', "") ++ ">" ++
    LiveView.esc(o(opts, 'value', "")) ++ "</textarea>"
}

# table — %{headers, rows}
# headers: list of strings. rows: list of lists of strings (or raw HTML cells).
fun table(opts) {
    hdrs = map_get(opts, 'headers')
    rows = map_get(opts, 'rows')
    head = if (hdrs == nil || length(hdrs) == 0) { "" }
           else { "<thead><tr>" ++ table_ths(hdrs, "") ++ "</tr></thead>" }
    body = if (rows == nil || length(rows) == 0) { "" }
           else { "<tbody>" ++ table_rows(rows, "") ++ "</tbody>" }
    "<div style=\"overflow-x:auto\"><table class=\"ui-table\">" ++ head ++ body ++ "</table></div>"
}

fun table_ths(hdrs, acc) {
    if (hdrs == nil || length(hdrs) == 0) { acc }
    else { table_ths(tl(hdrs), acc ++ "<th>" ++ LiveView.esc(to_string(hd(hdrs))) ++ "</th>") }
}

fun table_rows(rows, acc) {
    if (rows == nil || length(rows) == 0) { acc }
    else { table_rows(tl(rows), acc ++ "<tr>" ++ table_tds(hd(rows), "") ++ "</tr>") }
}

fun table_tds(cells, acc) {
    if (cells == nil || length(cells) == 0) { acc }
    else { table_tds(tl(cells), acc ++ "<td>" ++ LiveView.esc(to_string(hd(cells))) ++ "</td>") }
}

# tabs — %{tabs: [{id, label, content}], active?}
# Purely client-side switching via sw-js="tab:<id>". The first tab (or
# the one matching `active`) is shown; the rest are hidden. No server
# round-trip on tab change.
fun tabs(opts) {
    items  = map_get(opts, 'tabs')
    active = o(opts, 'active', "")
    first  = if (items == nil || length(items) == 0) { nil } else { hd(items) }
    act_id = if (active == "" && first != nil) { to_string(map_get(first, 'id')) }
             else { active }
    if (items == nil || length(items) == 0) { "" }
    else {
        bar     = tabs_bar(items, act_id, "")
        panels  = tabs_panels(items, act_id, "")
        "<div><div class=\"ui-tabs\">" ++ bar ++ "</div>" ++ panels ++ "</div>"
    }
}

fun tabs_bar(items, act_id, acc) {
    if (items == nil || length(items) == 0) { acc }
    else {
        it  = hd(items)
        id  = to_string(map_get(it, 'id'))
        lbl = to_string(map_get(it, 'label'))
        cls = if (id == act_id) { " ui-tab-active" } else { "" }
        btn = "<button class=\"ui-tab" ++ cls ++ "\" sw-tab=\"" ++ id ++
              "\" sw-js=\"tab:" ++ id ++ "\">" ++ LiveView.esc(lbl) ++ "</button>"
        tabs_bar(tl(items), act_id, acc ++ btn)
    }
}

fun tabs_panels(items, act_id, acc) {
    if (items == nil || length(items) == 0) { acc }
    else {
        it      = hd(items)
        id      = to_string(map_get(it, 'id'))
        content = to_string(map_get(it, 'content'))
        disp    = if (id == act_id) { "" } else { "display:none;" }
        panel   = "<div id=\"" ++ id ++ "\" sw-tab-panel style=\"" ++ disp ++ "\">" ++
                  content ++ "</div>"
        tabs_panels(tl(items), act_id, acc ++ panel)
    }
}
