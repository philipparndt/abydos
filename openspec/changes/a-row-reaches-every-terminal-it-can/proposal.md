## Why

The running-sessions list shipped yesterday and was used for an afternoon. Three
things came back, 2026-09-03:

- **It is wasteful in height, and it does not filter or scroll.** Every row is
  two lines with a blank around them, so nine sessions fill a screen, and a
  machine with a dozen has rows below the popover's edge with no way to reach
  them.
- **A row reaches only the tmux window this panel mirrors, and only while the
  `tmux` tab is in front.** A session in one of the panel's own terminal tabs,
  in another window's tab, in another tmux session, or in another pane of a
  tmux window, is "elsewhere" and copies a resume command — when the tab it
  is in is one click away.
- **It does not say which sessions the app cannot reach.** A session in a
  Ghostty window looks exactly like one in the tab next door until it is
  clicked, and the toast that says "Copied" is the first sign.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-03 — "The popup menu is a bit too wasteful in height and also
needs a filter and scrolling … I want to be able to jump to every terminal tab
(tmux/plain), as well as different tmux sessions/panes … It shall be clear that
a session is outside of abydos and we cannot jump there".

## What Changes

- **A pane names itself to what runs in it.** Every terminal the panel starts
  puts `ABYDOS_TERMINAL=<tab identity>` in its shell's environment, beside the
  `TERM_PROGRAM` it already sets rather than inherits. The hook reads it when
  it is not inside tmux and sends it with the event; inside tmux it sends the
  pane id as well as the window.
- **A row reaches everything the app can reach.** In order: the tab whose
  identity the session named, in this window or another, is brought forward;
  a session in the mirrored tmux session has its window and pane selected; a
  session in another tmux session has this panel's client switched to it, or
  a `tmux` tab attached to it when there is none, and then its window and pane
  selected. None of this needs the `tmux` tab to be in front.
- **A session the app cannot reach says so before it is clicked.** A row with
  neither a tab identity the app knows nor a tmux place is drawn dimmed and
  marked *elsewhere*, and clicking it copies the resume command, as before —
  the one thing the app can offer for a session it does not hold.
- **The list is a list.** One line per row — badge, name, last line, age — a
  filter field at the top that narrows the rows as it is typed into and
  chooses the first match on ⏎, and a scroll view bounded to a sensible
  height, so a dozen sessions are a dozen rows and not a screen.

## Capabilities

### Modified Capabilities

- `running-sessions`: the popover's requirement gains the filter, the scroll
  and the one-line row; the row's requirement is rewritten around what a
  click reaches and what it says when it cannot.
- `terminal`: gains a requirement that a pane names itself to the programs it
  runs, so a hook in one can say which tab it is in.

## Impact

- **AbydosKit**: `ClaudeHookRunner.announce` adds `pane` and `terminal`;
  `RunningSessions.Session` keeps both; `TmuxMirror.select(pane:)`;
  `PseudoTerminal.startLoginShell` takes an environment.
- **AbydosApp**: `TerminalView` carries a launch environment;
  `BottomPanel` names each tab's shell and gains the reach — activate a tab,
  reveal a window and pane, switch or attach a tmux client; `AppDelegate`
  lets one window's row reach another window's tab; `RunningSessionsPopover`
  is rebuilt with a filter field, a scroll view and one-line rows.
- **Driver**: the popover report says each row's reach, and a filter can be
  typed into a driven run.
- **Cost**: one environment variable per shell; nothing per event.
