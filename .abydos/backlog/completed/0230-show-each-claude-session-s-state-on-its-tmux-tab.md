# Show each Claude session's state on its tmux tab

`b79063f09` · 2026-08-03

cmanager already works out what tmux cannot know on its own — which panes
are Claude sessions and what they are doing — and writes it onto the
window as the `@ai_status` user option. tmux hands user options to a
format like any other field, so the strip can read it in the query it
already makes every half second: no extra process, no polling of our own,
and nothing at all when cmanager is not installed.

On the tab, where the ✕ would be if a tmux window had one: `⋯` working in
grey, `!` needs you in amber, `✓` finished in green. Bare marks rather
than the ringed or filled ones, because at the size a tab badge can be a
`.circle.fill` is a dot and telling "needs you" from "finished" would come
down to colour alone.

The format is now fixed at five fields rather than accepting the older
four, since a window called "one; two" would otherwise be
indistinguishable from a line carrying a status.
