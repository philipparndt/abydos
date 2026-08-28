# The debugger lists its breakpoints

## Why

A breakpoint is drawn in the gutter of the file it is in, and nowhere else. Two
breakpoints in one file are a glance; six across four files are a memory test,
and the only way to check one is to open the file it is in and look.

The evidence is a session file read this morning. `screencasts/.abydos/session.json`
held four breakpoints across three files — two in `Application.java`, two in a Go
service's `main.go` — and nothing in the window could show that. They were
carried in `DebugCoordinator.pendingBreakpoints`, written to disk on every tab
change, drawn in the gutter of whichever of the three files happened to be open,
and otherwise invisible. Three of them belonged to projects that were not even
the one on screen, which is how they were found at all: by reading the JSON.

There is already a command about breakpoints in the plural — `setOtherBreakpoints`,
"silence every breakpoint but one" — and the only way to reach it is to
right-click one of them in a gutter. A verb about the whole set, offered from a
view that shows one of them.

The natural place to show them is the debugger, and the debugger cannot be
opened. `DebugPane` is constructed with a `DebugSession`
(`DebugPane.init(session:projectRoot:)`), `makeDebugSession` is the only thing
that ever constructs one, and `BottomPanel.showDebug()` returns nil when no
session has made a pane. So the rail's ladybird button, pressed with nothing
running, has nothing to open — and `ToolWindowBar.debugButtonPressed()` pops a
menu asking *how to start a session* instead: Debug Go Package, Debug
Executable…, Attach to Process….

That menu is in the wrong place twice over. The rail's buttons open panes —
that is what the rail is, and every other button in it does only that. And the
window already has a control whose whole subject is starting things: the run
control in the titlebar, with a play button, a ladybird beside it, and a chevron
that opens a menu of the other ways to start (Debug, Profile, Run with
Coverage). "Attach to Process…" belongs in that menu, next to the other answers
to "start something", and not on a button whose job is to show a pane.

## What Changes

- The debug pane gains a **Breakpoints** tab beside the call stack, mirroring the
  Variables and Console tabs already on the right-hand side. It lists the
  project's breakpoints — file, line, the code the line holds, and the condition
  where there is one — and each row can be enabled, disabled, deleted, jumped to,
  and given a condition. It is the same set the gutter draws and the same set
  written to `.abydos/session.json`, shown as a list rather than one file at a
  time.
- **The debug pane opens with nothing running**, on its Breakpoints tab. A pane
  that exists only once a program does is the reason there was nowhere to put
  this.
- **The rail's debug button only opens the pane.** The menu of ways to start a
  session is removed from it; the button becomes what every other rail button
  is. **BREAKING** for anybody who reaches Attach to Process from the rail.
- **The ways to start a session move to the titlebar's debug button** — the
  ladybird in the run control. Its chevron menu gains "Debug Executable…" and
  "Attach to Process…" beside the Debug it already offers, and "Debug Go
  Package" where the project is a Go one. Pressing the ladybird itself still
  debugs the selected configuration, which is unchanged.
- The Run menu keeps its own "Attach to Process…" item, which is already there
  and is not the rail's.

## Capabilities

### New Capabilities
- `breakpoint-list`: seeing every breakpoint a project has as a list — where it
  is, what line it is on, whether it is enabled and what condition it carries —
  and acting on one from there. Includes the debug pane being openable with
  nothing running, since that is what gives the list somewhere to live.
- `starting-a-debug-session`: where the ways to start a session are offered. The
  titlebar's ladybird and its menu are the one place that asks what to debug;
  the panes that show a session do not ask.

### Modified Capabilities
- `left-rail`: the debug button opens the debug pane whether or not a session is
  running, rather than asking how to start one when none is. What the button's
  fill and colour mean is unchanged, and the case the rail already specifies —
  "the debug pane in front with no session running" — becomes reachable on
  purpose rather than only as the leftover of a session that ended.

## Impact

- `DebugPane` learns to exist without a session. Its left-hand side becomes
  tabbed the way its right-hand side already is, and the toolbar's verbs are
  disabled rather than absent while nothing is running.
- `BottomPanel.showDebug()` gains the case it does not have: making the pane when
  there is none. `makeDebugSession` already closes an existing debug pane before
  opening its own, so a session starting takes over the empty one rather than
  leaving two.
- `DebugCoordinator` is the list's source. It already holds the whole set for
  the project — `pendingBreakpoints`, kept in step with a running session's — and
  already carries every verb the rows need: `toggleBreakpoint`,
  `setBreakpoint(file:line:enabled:)`, `deleteBreakpoint`, `setBreakpointOptions`,
  `setOtherBreakpoints`. What it lacks is a way to say the set changed, which the
  gutter does not need because it is told file by file.
- `ToolWindowBar` loses `onDebugGoPackage`, `onDebugExecutable`, `onAttachToProcess`
  and `isGoProject`; `MainWindowController+Layout` loses the four wirings.
- `RunControl.showStartMenu()` gains the three entries and `RunCoordinator` the
  hooks behind them. `attachToProcess`, `debugExecutable` and `goDebug` are
  unchanged — they move ends, not bodies.
- Nothing changes in `AbydosKit`: `Breakpoint` already carries everything a row
  shows, and the DAP side is untouched.
