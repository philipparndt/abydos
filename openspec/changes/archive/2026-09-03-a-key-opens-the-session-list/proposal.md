## Why

The running-sessions list is reachable only by clicking the pill on the
terminal panel's title bar — and only when the panel is open, since the pill
lives on it. The list answers "is anything waiting for me, and where" for the
whole machine, which is a question worth asking without first finding a panel
and aiming at a 70-point control.

Asked for on 2026-09-03: a keyboard shortcut to open it, opened centred "like
Spotlight search"; ⇧⌘A was chosen from what the menus leave free. And: "show
this in the normal popup so that the users notice this" — a shortcut nobody can
see is a shortcut nobody has, which is the argument the titlebar capsule was
already drawing `⇧⌘P` under.

## What Changes

- **⇧⌘A opens the list**, from the Agent menu, which is where the agent verbs
  already live. It works with the panel closed, and needs no pill.
- **The keyboard route is a palette centred over the window**, near the top,
  the shape `SymbolPalette` already uses for "a list you filter and choose
  from". The pointer route stays the popover hanging off the pill, which
  explains the pill.
- **One list in both.** The filter, the rows, the arrows, ⏎ and Escape are the
  same view and the same controller; only the host differs.
- **The popover says `⇧⌘A`**, dimmed at the trailing edge of its filter row,
  where the titlebar capsule already says `⇧⌘P` — so somebody who found the
  list by clicking learns the key that gets them there next time.

## Capabilities

### Modified Capabilities

- `running-sessions`: gains the shortcut, the centred presentation for it, and
  that the popover advertises the key.

## Impact

- **AbydosApp**: a `RunningSessionsPalette` hosting the existing
  `RunningSessionsController` in a child window; `PanelRunningSessions` gains a
  second way to present the list it already builds; a menu item and a
  `MainWindowController` action; the filter row gains a dimmed shortcut label.
- **Driver**: a flag that opens the list by the key rather than the pill, so
  both routes are driven.
- **Cost**: none. The list is built from the register either way.
