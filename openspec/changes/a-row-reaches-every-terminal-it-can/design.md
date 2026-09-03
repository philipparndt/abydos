## Context

The hook says where a session is only when it is inside tmux: `TMUX_PANE` is
in its environment, and `display-message` turns that into a session name and a
window index. Outside tmux the hook knows the session's `cwd` and nothing about
the terminal around it. The panel's terminals set `TERM_PROGRAM` and
`IDEAI_APP` for the shells they start, deliberately rather than by inheritance,
because an inherited value was a lie. Each panel tab has an `identity`, a UUID,
that outlives a rebuild.

`BottomPanel` can already activate one of its sessions, reveal a tmux window
in the mirrored session, switch its tmux client to another session
(`switchToSession`, from the tag's menu) and attach a fresh `tmux` tab to a
session (`reattachTmux`). The pieces exist; nothing joins them for a row.

## Goals / Non-Goals

**Goals:**

- A click on a row lands in the terminal the session is in whenever that
  terminal is one of ours, in any window, in any tmux session or pane.
- A row the app cannot reach looks different before it is clicked.
- A list that scales to a dozen sessions: one line each, filter, scroll.

**Non-Goals:**

- Reaching a session in another app's terminal. The resume command is the
  only honest offer, and it stays.
- Reaching a session over a remote tmux socket. One machine, one user, as
  the register already says.
- Keyboard navigation of the rows beyond ⏎ on the filter. Arrow keys in a
  drawn list are a change of their own.

## Decisions

**The tab names itself in the environment, and the hook passes the name on.**
`ABYDOS_TERMINAL=<identity>` goes into every shell the panel starts, through
`TerminalView`'s launch and `PseudoTerminal.startLoginShell`. The hook sends it
only when `TMUX_PANE` is absent: inside tmux the variable is the tmux server's
inheritance — the tab that started the server, possibly long ago, possibly
closed — and the tmux place is the truth.

*Ruled out: matching a session to a tab by its `cwd`.* Two tabs in one
project are the ordinary case, and the wrong one is worse than the resume
command.

*Ruled out: the app asking each pane's process tree for a `claude`.* A walk of
the process table per event, to learn what one variable says for free.

**The reach is decided once, in the panel, and drawn from the same answer.**
`BottomPanel.reach(of:)` returns *tab here*, *tab in another window*, *tmux*,
or *elsewhere*, and `reveal(_:)` acts on the same enumeration. The list asks
`reach(of:)` to draw a row and `reveal(_:)` to click it, so what the row says
and what it does cannot drift.

**Another window's tab is reached through the app.** The panel knows its own
tabs. `AppDelegate` gives the presenter two closures over every window: the set
of tab identities the app holds, and a reveal that brings the owning window
forward and activates the tab there. The register stays the machine's; the
reach is the app's.

**A tmux place is always reachable while tmux is.** Same session as the
mirror: select the window and the pane. Another session: switch this panel's
client to it (`switch-client`), then select. No `tmux` tab at all: attach one
to the session (`reattachTmux`), then select. Selecting the pane by its id
(`%7`) rather than the window index, because the id is global to the server
and survives the window being renumbered.

*Ruled out: opening a second `tmux` tab when the panel already has one.* Two
clients from one panel on two sessions is two strips of tabs claiming to be
the panel's windows.

**One line per row.** Badge, the window name or the last line, the last line
dimmed after it when the name took the title, the age at the right. The
two-line row was reading room for a message that is one glance long. A row
marked *elsewhere* is drawn in the dim ink with the word at its right, before
the age.

**Filter and scroll are the switcher's.** `ScaledSearchField` above an
`NSScrollView` around the drawn list, the popover's height bounded, the field
first responder on open, ⏎ choosing the first visible row. Typing filters by
project name, window name and last line together; the groups that end up empty
are not drawn.

## Risks / Trade-offs

**A tab that started a tmux server hands `ABYDOS_TERMINAL` to every pane in
it** → The hook prefers the tmux place whenever `TMUX_PANE` is set, so the
variable is read only where it is true.

**Switching the panel's tmux client changes what its tabs show** → That is
what "go to that session" means, and the tag's menu already offers exactly
this. The strip follows the client.

**Attaching a `tmux` tab to another project's session pulls the window there
when it follows its terminal** → Following is off by default, and a person who
turned it on asked for the window to follow the shell.

## Open Questions

- Whether a row should offer the resume command *as well* when it is
  reachable — a context menu, say — for somebody who wants the session in a
  new tab rather than the old one. Not in this change.
