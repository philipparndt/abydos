# 448. A terminal inherits a tmux socket path that cannot exist

Opening a terminal produced this, and nothing else:

    [process exited with status 1]
    error connecting to /private/tmp/claude-501/-Users-philipparndt-dev-abydos/
    623b9d92-…/scratchpad/t0404/tmuxdir/tmux-501/default (File name too long)

The pane is dead on arrival and the sentence is tmux's, not ours — so from the
outside it reads as the terminal being broken, with a path in it that has nothing
to do with the project somebody opened.

## What happened

A unix socket path on macOS is capped at about 104 bytes. That one is about 140.
`TMUX_TMPDIR` was set in the environment the app was launched from, the app hands
its environment to the shell it starts, and tmux appends `tmux-<uid>/default` to
whatever `TMUX_TMPDIR` says. Nothing between the launch and the failure looks at
whether the result can exist.

How the variable got there is not the app's fault and is worth recording anyway,
because it is the shape of the thing rather than a one-off: an agent ran
`export TMUX_TMPDIR=…` and `tmux new-session` in one command, that command
happened to *start* the default server, and tmux copies its global environment
into every pane it creates. So every shell on that machine carried it for the
next nine hours, and every Abydos launched from one of them inherited it.
Removed with `tmux set-environment -gu TMUX_TMPDIR`.

## Why this is ours to answer even though the value came from outside

The app already does exactly this for the neighbouring variable. 0440 found that
`$TMUX` leaked in from whatever shell launched the app, so a pane that was *not*
inside tmux wrapped its escapes in a passthrough nobody would unwrap and fell
back in silence — and `PseudoTerminal.mergedEnvironment` strips it. This is the
same family, one variable along, and the failure is louder but no more
explicable to the person looking at it.

A value that cannot produce a usable socket path is not a preference to be
honoured. It is a value to be refused, with a sentence saying so.

## Ruled out

Nothing yet — written before the work.

Worth knowing: the fix is *not* to unset `TMUX_TMPDIR` unconditionally. Somebody
who has set a short, valid one means it, and taking it away would put their panes
on a different server from their other tools — which is the same class of mistake
as ignoring somebody's PATH. The test is whether the path it produces fits, not
whether the variable is present.

## Steps

- [ ] Work out the real limit rather than assuming 104: `sizeof(sun_path)` on
      this platform, less what tmux appends (`tmux-<uid>/` and the socket name)
- [ ] Refuse a `TMUX_TMPDIR` whose socket path would not fit, and say so in the
      pane instead of letting tmux say "File name too long"
- [ ] A short, valid `TMUX_TMPDIR` is still honoured — a test for both sides
- [ ] Check whether anything else the app hands to a subprocess has the same
      shape: a value inherited, passed on, and only failing much later
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
