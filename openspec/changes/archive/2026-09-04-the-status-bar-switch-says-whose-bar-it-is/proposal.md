## Why

Reported: the help for **Hide tmux's own status bar** says nothing else is
harmed, and that is not what happens — the session being used loses its status
line. Asked to be more precise.

The words were "Set on the session as it is attached — nothing is written to
~/.tmux.conf, and other sessions keep their bar." Every clause is true, and
together they read as "this does not reach my tmux elsewhere". It does. The
switch runs `set-option -t <session> status off`, and a session option belongs
to the *session*, not to this app's client: every terminal attached to that
session draws no bar either, inside Abydos or not, then and later. Nothing puts
it back when the app quits.

A help text that is true clause by clause and wrong in what it leaves somebody
believing is worse than a short one, because it is the sentence they act on.

## What Changes

- **The help says the whole shape**: which session, that other sessions and
  `~/.tmux.conf` are untouched, that the named session loses its bar in every
  terminal attached to it, and that it stays off after Abydos quits until the
  switch is turned back on.
- **The toast says the same**, and says something different when the bar comes
  back — `-u` restores whatever that session's own config says, which is not
  the same sentence as taking it away.
- **The two doc comments** that set up the same impression are corrected where
  the code is, including why the old wording misled.
- **`terminal` gains the requirement**, so the account states the scope rather
  than leaving it to a help string.

## Capabilities

### Modified Capabilities

- `terminal`: says what hiding tmux's status bar reaches, and for how long.

## Impact

- **Driver**: `--settings-says "Page/Row"` prints what a row says. Nothing
  could read a help text from a run before — every settings verb sets a value
  or photographs the page — which is how a wrong sentence below the fold
  survived to be reported from the outside.
- **Words only, otherwise.** No behaviour changes: the option, its scope and its lifetime
  are what they were. What changes is that somebody reading the switch can tell
  what it will do to a session they are attached to in another terminal.
