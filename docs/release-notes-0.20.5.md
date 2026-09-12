# Abydos 0.20.5

## A styled link a program writes is a link in the pane

A hyperlink marked with OSC 8, such as Claude Code's `#211` for a pull
request, arrived as plain text. The tmux client now says it shows hyperlinks,
and a pane without tmux sets `FORCE_HYPERLINK`.

## A styled link opens on a click

A marked link is underlined with a hand pointer on hover, no ⌘ needed, a
tooltip says where it goes, and a plain click opens it. Dragging still
selects, and Shift forces a selection. A plain printed address keeps the ⌘
rule from 0.20.4.
