# Hide tmux's bar for one session, not for everybody

`36374b918` · 2026-08-04

Your link is the right instinct — do it without touching the config file
— but the trick in it only fires when ideai is the process that starts
the tmux server. Proven: with the server already running, a session
ideai creates still gets a status bar, because the `if-shell` ran once,
long ago, in somebody else's environment.

The option itself is per session, which is what was wanted all along:

    set-option -t <session> status off

Measured against an isolated config, that turns the bar off for one
session and leaves every other session, and every other terminal
attached to them, exactly as they were. The earlier "it never really
worked" was our own phantom row leaving a stale line on screen, not tmux
failing to honour it.

So the config edit is gone. The checkbox is a wish that is remembered
whether or not it can be granted now, applied to the session each panel
attaches to; turning the tabs off gives the bar straight back. The block
the previous version wrote is taken out once on launch, since a global
`status off` takes the bar from Ghostty too.
