## Context

`TmuxSettings.wantsStatusBarHidden` is a wish; `BottomPanel.applyStatusBarWish`
grants it whenever the panel attaches, by way of
`TmuxMirror.setStatusBar(_:inSession:)`, which runs
`set-option -t <session> status off` — and `-u status` to put it back.

The scope is therefore the tmux *session* the panel attached to, named after the
project. Not the server, not global, not the config file. And not this app's
client either, which is the part the words missed.

## Goals / Non-Goals

**Goals:**

- Somebody reading the switch knows what it reaches and for how long.

**Non-Goals:**

- Changing the scope. A session option is the right one: the server-wide edit an
  earlier version wrote is what `migrateAwayFromConfigEdit` exists to undo.
- Restoring the bar when the app quits. That would mean writing to somebody's
  tmux on the way out, and a session that keeps the arrangement it was given is
  the lesser surprise — but it has to be *said*, which is this change.

## Decisions

**Say what it reaches before saying what it spares.** The old text led with the
reassurances — no config file, other sessions fine — and buried the subject.
The order is reversed: which session, what happens to it everywhere, then what
is untouched.

**Two toasts rather than one.** Turning it off is not the mirror image of
turning it on: `-u` restores whatever that session's own config says, which may
be a bar of any height or none. Saying "nothing was written to ~/.tmux.conf" as
the bar *returns* answers a question nobody asked.

**A requirement, not just a better string.** The claim is about what the app
does to something outside it, and the next person to reword the help should
meet a stated scope rather than their own reading of the code.

## Risks / Trade-offs

**A longer help text** → It is the longest in that section, and it is the only
switch there that changes something a person can see in another program.
