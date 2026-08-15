# Abydos 0.2.1

Fifty-nine commits since 0.2.0, and nearly all of them are the terminal. It draws
sixty frames a second where it drew one, output arrives at fifty megabytes a
second where it arrived at three, and the second terminal engine that shipped
switched-off-and-unwired in 0.2.0 is now a real choice.

## The terminal

**A build scrolling past used to be drawn once a second.** Not slowly — *once a
second*, on the ordinary engine, in a release build. The rule underneath asked
"are there bytes I have not parsed yet", and against a program producing output as
fast as it can be read that is always true, so the screen stopped being drawn and
stayed stopped. It asks how *stale* the picture is now — how long ago the oldest
unparsed byte came off the terminal — and anything under a quarter of a second is
the program's own picture and is drawn at the display's rate.

The old rule was written for a real fault and that fault is still handled: a
locked screen coming back, or a pane scrolled away and returned to, still draws
the picture the program means rather than replaying every frame it missed. Forty
thousand frames of a spinner produce three drawn frames, not forty thousand.

**Output is handed over in one piece rather than fifteen thousand.** Every read
from the terminal used to become its own hop to the main thread — fifteen
thousand a second under load, each one a message the interface had to process
before it could draw anything. They are merged now, and the backlog that was
hiding in that queue is gone with them.

**A newline no longer allocates a row.** Every line of output built a fresh row of
cells one reference count at a time and freed another the same way — four hundred
retains and releases for a single line feed, because a cell can hold a combining
mark and a row of them therefore cannot be copied in one go. The row a scroll
retires is reused, the cells are written field by field, and the grid turns
instead of being reassigned.

**Only the rows that changed are rebuilt.** A screen where one line moves — a
progress bar, a clock, a prompt rewritten under the up arrow — hands the renderer
two hundred and thirty-five cells instead of eleven thousand.

### What that adds up to

Measured in a pane, 235×47, on the same machine that produced the first column:

| | 0.2.0 | 0.2.1 |
|---|---|---|
| a build scrolling past | 3.3 MB/s, one frame a second | **48.5 MB/s, sixty** |
| the DOOM fire benchmark | 183 fps · 32.4 MB/s | **329 fps · 58.0 MB/s** |
| a prompt rewritten under ↑ | 11,045 cells a frame | **235** |

## The other engine

0.2.0 shipped libghostty-vt — ghostty's terminal state machine — behind a setting
that was registered and wired to nothing. It is wired now, and it is a fair
choice rather than a curiosity: on the same measurements it reaches sixty frames a
second and fifty-eight megabytes a second, against the built-in engine's sixty and
sixty.

Getting there meant finding that the app was copying every visible cell out of the
library fourteen hundred times a second in order to read a single integer. It no
longer does.

It stays **off by default**, and it says what it cannot do rather than guessing:
`abydos <file>` typed in a pane does not open it, xterm's `modifyOtherKeys`
sends ordinary bytes, and tmux's prompts draw one row too high when tmux's status
bar is switched off — which is a fault in that engine, reported and not worked
around.

## Measuring it yourself

`abydos-bench` — installed with the app — now runs nine patterns rather than two,
ten seconds each, and names each phase in the terminal's tab as it runs. The fire
and the rain were the only things anybody measured, which is why a build scrolling
past could be drawn once a second for weeks without being noticed. There is now a
pattern for ordinary log output, for a full scrollback, for a status line, for a
prompt rewritten under the up arrow, and for colours and glyphs separately.

## Also

A repository with no commits yet shows its branch, dimmed, rather than showing
nothing. Amend is disabled there instead of failing, and the branch menu opens
instead of not appearing.

The release itself is signed properly: every command-line tool inside the app —
`abydos-backlog` and `abydos-bench` — is signed with a Developer ID, which two of
them were not in 0.2.0.
