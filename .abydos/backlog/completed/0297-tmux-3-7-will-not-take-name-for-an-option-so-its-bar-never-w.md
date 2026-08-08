# tmux 3.7 will not take `=name` for an option, so its bar never went away

`725da4c8a` · 2026-08-05

The setting was on, the tabs mirrored, and the status bar stayed — on every
session this app created, with nothing anywhere saying why.

`set-option -t =<session>` is how every other target here is written: the `=`
means an exact name rather than a prefix. tmux 3.7 rejects it for `set-option`
and `show-options` — "no such session: =name" — while still accepting it for
`list-windows`, `new-window` and `display-message`. So the half of the
integration that lists windows kept working and the half that hides the bar
failed silently, which is why it looked like a setting that did nothing.

A plain name is a prefix match, which is weaker than what was meant, and safe
enough: tmux resolves an exact name before any prefix.

Found photographing the app for the documentation — a fresh session showed the
bar, while the session this window has been attached to all along still had
`status off` from before, applied when the syntax still worked.
