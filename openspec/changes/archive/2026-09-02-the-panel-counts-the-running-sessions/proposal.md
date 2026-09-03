## Why

Every Claude Code session on the machine already tells Abydos what it is doing:
the hook posts a distributed notification on every event, `RunningSessions`
keeps the set of running sessions per project, the tmux window tabs wear a badge
for the session in them, and a toast says a line when a session in another tab
speaks. What none of that answers is the question asked from across the room —
**is anything waiting for me, and where?** The tabs only know the windows of the
one tmux session this window mirrors; the toast is gone in seconds; the
navigator's `Claude Sessions` root lists one project and is usually scrolled
away or behind another tool window.

The evidence is the screenshot that prompted this, 2026-09-02: a maximised
terminal panel with eight tmux windows on its strip, a spinner on `screencasts`
and a tick on `cluster-ctl`, and no way to know that a session in another
project on the same machine had been sitting at a permission prompt. Six
placements were drawn against the real chrome and compared — a pill on the
panel's title bar, a rail button with a tool window, a segment on the tmux
strip, a node in the navigator, a column on the project switcher, a strip in
the toast corner — and the pill was chosen: it is the only one with both a
strong glance and a full list that adds no chrome when nothing is running.
The comparison is at
https://claude.ai/code/artifact/cdb050a4-c70b-476f-8278-81f3d16b936a.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-09-02 — "it shall be possible to have an overview of all claude
sessions that are currently running … see at a glance what is currently
running", followed by "go with A".

## What Changes

- **A pill on the terminal's title bar**, left of the `tmux · session` tag among
  the panel strip's trailing controls, summarising every running Claude Code
  session on the machine as two counts: how many are **working** (blue) and how
  many **need input** (amber). It uses the vocabulary the tab badges already
  use. A finished session is listed but never counted, and a working session
  that has said nothing for longer than the tabs' own staleness bound is shown
  hollow and not counted as working. The pill is **not drawn at all** when
  nothing is running, so an idle panel looks as it does today.
- **A popover under the pill** listing every running session grouped by
  project, the window's own project first. A row carries the status, the tmux
  window it is in when the hook could say, its last announced line and how long
  ago that was. Clicking a row in the tmux session this window mirrors reveals
  that window, which the toast's action already does; clicking any other row
  copies the resume command, which the navigator's session rows already do.
- **The register remembers more than membership.** `RunningSessions` keeps, per
  session, what the hook last said — status, tmux place, line, time — so the
  pill and the popover are drawn from it and nothing here reads a disk or asks
  a process. Windows mirrored here are also seeded from tmux's own
  `@ai_status`, so a session that was running before the app launched is not
  invisible until its next event.
- **A driven run can show it**: `--claude-running` grows to say a status, so a
  picture of the pill and the popover can be taken at all. A driven run still
  subscribes to nothing, as the screenshots capability already requires.

## Capabilities

### New Capabilities

- `running-sessions`: what the app knows about the Claude Code sessions running
  anywhere on the machine, and how the terminal panel summarises and lists them
  — the pill's counts, when it is absent, what a row says, what a click does,
  and what the driven run can be told.

### Modified Capabilities

- `terminal`: the requirement that the panel's own controls are drawn on a
  ground of their own names the controls it protects — the session tag, follow,
  maximise, hide — and the sessions pill joins that list, so a tab strip full of
  tabs hides a tab under it rather than drawing a name through it.

## Impact

- **AbydosKit**: `RunningSessions` gains a per-session record and the queries
  the pill and popover ask — counts by shown status, sessions grouped by
  project — and `TmuxMirror.Window.staleAfter` becomes the one bound both the
  tabs and the pill use. No view code; all of it testable without a window.
- **AbydosApp**: `PanelTabStrip` gains a trailing control and a click callback
  beside `onMirrorTagClicked`; `BottomPanel` owns the popover and hands rows to
  `MainWindowController.revealTmuxWindow` or the pasteboard; `ClaudeWatch`
  keeps feeding the register and tells every window to redraw the pill when
  `note` says the answer moved. `LaunchOptions.claudeRunning` learns a status.
- **Driver**: the pill's counts and the popover's rows are readable, so the
  claims in the tasks can be checked.
- **Cost**: the hook's tool-use events arrive dozens of times a minute; the
  register already answers "nothing changed" for them, and the pill redraws only
  when `note` returns a slug. One 70‑point control on the strip, and none when
  idle.
- **Depends on** `the-zoom-reaches-every-control` for the control it is drawn
  with, so the pill is not born unscaled.
