## Why

**The backlog button is never lit, and the terminal button is lit for the wrong
reason.** Reported with a picture of the rail: the backlog pane was open and in
front, and the button that opened it looked exactly like a button nobody had
pressed, while the terminal button below it carried the selected fill.

Neither half is an accident of drawing. `ToolWindowBar` assigns `isSelected` in
three places and the backlog is in none of them:

- `setSidebarSelection(visible:tool:)` lights whichever of the six *sidebar*
  buttons the sidebar is showing, and nothing when it is closed. That rule is
  right and this change does not touch it.
- `setTerminalSelected(_:)` is called from `MainWindowController.setPanelVisible`
  and nowhere else, so it means **"the bottom panel is open"** — which is why the
  terminal is lit in a picture of the backlog. Its own comment says as much:
  *"Lights the terminal button while the panel is showing."*
- `setDebugRunning(_:)` lights the ladybird while a debug session is running,
  *"so the strip says something is being debugged even when the panel is
  closed"* — a different thing again, and a deliberate one.

`backlogButton.isSelected` and `reviewButton.isSelected` are never written at
all. So four buttons sit in one group at the bottom of the rail under three
different meanings of the same fill, and the two most recently added have none.

**Lighting the backlog on its own would make it worse**, which is why this is
not a one-line change: with the panel open on the backlog, the backlog *and* the
terminal would both be lit, and the rail would be answering "which pane is in
front" with two answers.

No originating backlog item: the backlog was dropped on 2026-08-19, and this was
reported on 2026-08-22.

## What Changes

- **The bottom group follows the rule the sidebar group already keeps.** A
  button is lit when the panel is showing that kind of tab, and nothing is lit
  when the panel is closed. One meaning of the fill for the whole rail.
- **The backlog button gains selection**, which is what was asked for.
- **The terminal button stops meaning "the panel is open"** and starts meaning
  "a terminal is the tab in front".
- **The review button gains it too.** It is in the same group and drawn the same
  way, and leaving one of four unlit is the state this is fixing.
- **The debug button keeps what it says and gains what it was missing.** It is
  lit when the debug tab is in front, *and* while a session is running with the
  panel closed — that second signal is not this change's to take away.
- **A running session turns the ladybird green**, so the two reasons can be told
  apart rather than sharing one fill. The rail already does this: the commit
  button is blue for uncommitted work and green — `Theme.current.gitAdded` — for
  work not pushed, and `StripButton` already composes an accent colour on the
  icon with the fill behind it. Nothing new is drawn.
- **Not proposed: a rule for the sidebar group.** It already has one, it is
  right, and the fault is entirely below the separator.
- **Not proposed: making the panel's own tab strip say anything different.** It
  already says which tab is in front; the rail is what disagrees with it.

## Capabilities

### New Capabilities

- `left-rail`: what the strip down the left edge of the window says — which of
  its buttons is lit, when, and what a colour on one means. The rail's buttons
  are described today only where the feature behind one is described (the
  `backlog` capability says the backlog has a button on it), and no capability
  owns the rule that decides which is lit.

### Modified Capabilities

<!-- None. `backlog` says the rail carries a button that opens the backlog,
     which stays true and unchanged; what that button *looks like* is not a
     thing it claims. -->

## Impact

- `Sources/AbydosApp/ToolWindowBar.swift` — the three setters become one rule for
  the bottom group, and the ladybird gains a colour.
- `Sources/AbydosApp/MainWindowController.swift` — `setPanelVisible` stops being
  the thing that decides what the terminal button says, and the panel's active
  tab starts being it.
- `Sources/AbydosApp/Panel/BottomPanel.swift` — which kind of tab is in front has
  to be askable, and a change of it has to be announced. `onActiveTerminalChanged`
  is the existing hook and is named for a narrower question than it now answers.
- No new dependency, nothing drawn that `StripButton` cannot already draw.
