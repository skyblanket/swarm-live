module Main

# swarmUI showcase — every component on one live page.
#
#   bin/swc build studio/ui_showcase_lv.sw -o /tmp/ui_showcase
#   /tmp/ui_showcase      ->  http://localhost:4005

import LiveView
import UI

fun mount(params) {
    %{count: 0, switch_on: 'false', progress: 60, name: ""}
}

fun render(assigns) {
    count = map_get(assigns, 'count')
    sw_on = map_get(assigns, 'switch_on')
    prog = map_get(assigns, 'progress')
    name = map_get(assigns, 'name')
    greeting = if (string_length(name) > 0) { "Hello, " ++ name ++ "." }
               else { "Type your name above." }

    buttons_card = UI.card(%{
        title: "Buttons",
        description: "Six variants, three sizes, a live counter.",
        content:
            "<div style=\"display:flex;flex-wrap:wrap;gap:.5rem\">" ++
            UI.button(%{label: "Default"}) ++
            UI.button(%{label: "Secondary", variant: "secondary"}) ++
            UI.button(%{label: "Destructive", variant: "destructive"}) ++
            UI.button(%{label: "Outline", variant: "outline"}) ++
            UI.button(%{label: "Ghost", variant: "ghost"}) ++
            UI.button(%{label: "Link", variant: "link"}) ++
            "</div>" ++
            "<div style=\"display:flex;gap:.5rem;align-items:center;margin-top:.75rem\">" ++
            UI.button(%{label: "Small", size: "sm"}) ++
            UI.button(%{label: "Default"}) ++
            UI.button(%{label: "Large", size: "lg"}) ++
            "</div>" ++
            "<div style=\"display:flex;gap:.6rem;align-items:center;margin-top:1.1rem\">" ++
            UI.button(%{label: "-", event: "dec", variant: "outline", size: "sm"}) ++
            "<span style=\"font-size:1.4rem;font-weight:600;min-width:2.5rem;text-align:center;" ++
            "font-variant-numeric:tabular-nums\">{{}}</span>" ++
            UI.button(%{label: "+", event: "inc", variant: "outline", size: "sm"}) ++
            "</div>"
    })

    form_card = UI.card(%{
        title: "Form",
        description: "Inputs stream to the server via sw-input.",
        content:
            UI.label("Name") ++
            UI.input(%{name: "name", placeholder: "what's your name?",
                       event: "name_input", value: "{{}}"}) ++
            "<p style=\"margin-top:.85rem;font-size:.875rem;color:hsl(var(--muted-fg))\">{{}}</p>",
        footer: UI.button(%{label: "Submit", variant: "default"}) ++
                UI.button(%{label: "Cancel", variant: "ghost"})
    })

    badges_card = UI.card(%{
        title: "Badges &middot; Avatars &middot; Tooltip",
        content:
            "<div style=\"display:flex;flex-wrap:wrap;gap:.5rem;align-items:center\">" ++
            UI.badge(%{label: "Default"}) ++
            UI.badge(%{label: "Secondary", variant: "secondary"}) ++
            UI.badge(%{label: "Destructive", variant: "destructive"}) ++
            UI.badge(%{label: "Outline", variant: "outline"}) ++
            "</div>" ++
            "<div style=\"display:flex;gap:.6rem;align-items:center;margin-top:1.1rem\">" ++
            UI.avatar(%{text: "SW"}) ++
            UI.avatar(%{text: "LV"}) ++
            UI.avatar(%{text: "AK"}) ++
            "<span style=\"margin-left:1rem\">" ++
            UI.tooltip(%{label: "hover me", tip: "this is a tooltip"}) ++
            "</span></div>"
    })

    alerts_card = UI.card(%{
        title: "Alerts",
        content:
            UI.alert(%{title: "Heads up!", body: "You can compose any component into another."}) ++
            "<div style=\"height:.6rem\"></div>" ++
            UI.alert(%{title: "Something went wrong", body: "Your session has expired. Try again.",
                       variant: "destructive"})
    })

    interactive_card = UI.card(%{
        title: "Interactive",
        description: "Switch &amp; progress fire LiveView events; only changed dynamics cross the wire.",
        content:
            "<div style=\"display:flex;align-items:center;gap:.85rem;margin-bottom:1.25rem\">" ++
            "<span style=\"font-size:.875rem\">Notifications</span>" ++
            "{{}}" ++
            "</div>" ++
            UI.separator() ++
            "<div style=\"display:flex;justify-content:space-between;font-size:.85rem;" ++
            "color:hsl(var(--muted-fg));margin-bottom:.4rem\">" ++
            "<span>Progress</span><span>{{}}%</span></div>" ++
            "{{}}" ++
            "<div style=\"display:flex;gap:.5rem;margin-top:.9rem;align-items:center\">" ++
            UI.button(%{label: "-10", event: "prog_dec", variant: "outline", size: "sm"}) ++
            UI.button(%{label: "+10", event: "prog_inc", variant: "outline", size: "sm"}) ++
            "<span style=\"margin-left:auto\">" ++ UI.spinner() ++ "</span></div>"
    })

    skeleton_card = UI.card(%{
        title: "Skeleton",
        content:
            UI.skeleton(%{h: "1rem", w: "55%"}) ++
            "<div style=\"height:.5rem\"></div>" ++
            UI.skeleton(%{h: "1rem", w: "85%"}) ++
            "<div style=\"height:.5rem\"></div>" ++
            UI.skeleton(%{h: "1rem", w: "40%"})
    })

    dialog_card = UI.card(%{
        title: "Dialog",
        description: "Opened by a client-side JS command — no server round-trip.",
        content: UI.button(%{label: "Open Dialog", js: "show:#demo-dialog"})
    })

    dlg = UI.dialog(%{
        id: "demo-dialog",
        title: "Are you sure?",
        body: "Dialogs open via sw-js — purely client-side, no diff fired.",
        footer:
            UI.button(%{label: "Cancel", variant: "outline", js: "hide:#demo-dialog"}) ++
            UI.button(%{label: "Confirm", variant: "default", js: "hide:#demo-dialog"})
    })

    select_card = UI.card(%{
        title: "Select &amp; Textarea",
        description: "New in swarmUI — server-driven dropdowns and multiline inputs.",
        content:
            UI.label("Priority") ++
            UI.select(%{name: "priority", value: "medium",
                options: [ %{value: "low",    label: "Low"},
                           %{value: "medium", label: "Medium"},
                           %{value: "high",   label: "High"},
                           %{value: "urgent", label: "Urgent"} ]}) ++
            "<div style=\"height:.75rem\"></div>" ++
            UI.label("Notes") ++
            UI.textarea(%{name: "notes", placeholder: "write something...", rows: "3"})
    })

    table_card = UI.card(%{
        title: "Table",
        content: UI.table(%{
            headers: ["Component", "Type", "Status"],
            rows: [
                ["button",   "interactive", "stable"],
                ["card",     "layout",      "stable"],
                ["select",   "form",        "new"],
                ["textarea", "form",        "new"],
                ["table",    "data",        "new"],
                ["tabs",     "navigation",  "new"]
            ]
        })
    })

    tabs_card = UI.card(%{
        title: "Tabs",
        description: "Client-side tab switching — no server round-trip.",
        content: UI.tabs(%{tabs: [
            %{id: "tab-overview",  label: "Overview",
              content: "<p style=\"font-size:.875rem;color:hsl(var(--muted-fg))\">Tabs switch client-side via sw-js. No diff is fired on tab change — the server only knows if you wire a sw-click event.</p>"},
            %{id: "tab-usage",    label: "Usage",
              content: "<p style=\"font-size:.875rem;color:hsl(var(--muted-fg))\">UI.tabs(%{tabs: [{id, label, content}, ...], active?}) renders the tab bar and panels. Pass active: \"id\" to set the default.</p>"},
            %{id: "tab-notes",    label: "Notes",
              content: "<p style=\"font-size:.875rem;color:hsl(var(--muted-fg))\">Panels use sw-tab-panel; triggers use sw-tab and sw-js=\"tab:panel-id\". The active class is ui-tab-active.</p>"}
        ]})
    })

    LiveView.h(
        UI.css() ++
        "<div style=\"max-width:780px;margin:3rem auto 5rem;padding:0 1.25rem\">" ++
        "<h1 style=\"font-size:2.1rem;font-weight:700;letter-spacing:-.025em\">swarmUI</h1>" ++
        "<p style=\"color:hsl(var(--muted-fg));margin:.35rem 0 2rem\">" ++
        "shadcn-flavoured components on swarmrt LiveView</p>" ++
        buttons_card ++ "<div style=\"height:1.5rem\"></div>" ++
        form_card ++ "<div style=\"height:1.5rem\"></div>" ++
        badges_card ++ "<div style=\"height:1.5rem\"></div>" ++
        alerts_card ++ "<div style=\"height:1.5rem\"></div>" ++
        interactive_card ++ "<div style=\"height:1.5rem\"></div>" ++
        skeleton_card ++ "<div style=\"height:1.5rem\"></div>" ++
        dialog_card ++ "<div style=\"height:1.5rem\"></div>" ++
        select_card ++ "<div style=\"height:1.5rem\"></div>" ++
        table_card ++ "<div style=\"height:1.5rem\"></div>" ++
        tabs_card ++
        dlg ++
        "<div style=\"text-align:center;color:hsl(var(--muted-fg));font-size:.8rem;margin-top:3rem\">" ++
        "swarmUI &middot; on swarmrt LiveView</div>" ++
        "</div>",
        [ count,
          name,
          greeting,
          LiveView.raw(UI.switch(%{event: "toggle_switch", on: sw_on})),
          prog,
          LiveView.raw(UI.progress(%{value: prog })) ])
}

fun handle_event(name, value, assigns) {
    if (name == "inc") {
        LiveView.assign(assigns, 'count', map_get(assigns, 'count') + 1)
    }
    else { if (name == "dec") {
        LiveView.assign(assigns, 'count', map_get(assigns, 'count') - 1)
    }
    else { if (name == "toggle_switch") {
        cur = map_get(assigns, 'switch_on')
        LiveView.assign(assigns, 'switch_on', if (cur == 'true') { 'false' } else { 'true' })
    }
    else { if (name == "prog_inc") {
        p = map_get(assigns, 'progress')
        LiveView.assign(assigns, 'progress', if (p + 10 > 100) { 100 } else { p + 10 })
    }
    else { if (name == "prog_dec") {
        p = map_get(assigns, 'progress')
        LiveView.assign(assigns, 'progress', if (p - 10 < 0) { 0 } else { p - 10 })
    }
    else { if (name == "name_input") {
        LiveView.assign(assigns, 'name', to_string(value))
    }
    else { assigns }}}}}}
}

fun main() {
    LiveView.start(4005, %{
        title: "swarmUI",
        mount: mount,
        render: render,
        handle_event: handle_event
    })
}
