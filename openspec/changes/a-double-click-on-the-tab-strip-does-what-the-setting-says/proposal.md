## Why

The maintainer, 2026-09-10: *"I want a setting what a double click in the
editor header shall do: expanding/collapsing (default), create a local scratch
file (what it currently does), create a global scratch file."*

The header is the editor's tab strip, and a double-click on its empty part is
one line in `EditorTabBar+Mouse.swift`: `if event.clickCount == 2 {
onNewScratch?() }`, with the comment that this is what the editors people
arrive from do. It is what one family of them does. In the other family the
same gesture maximises the editor — hides the panels around it and gives it
back — which this strip already offers as a button (`maximizeButtonFrame`,
`onMaximize`) and which is the gesture the maintainer reaches for. Both are
reasonable; the strip has room for one; so it is a setting, with the
maintainer's choice as the default and the two scratches as the others.

A global scratch already exists as a place — the editor knows its directory
(`globalScratchDirectoryForTesting`) and the Scratches view lists both kinds —
but nothing in the strip makes one.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-10.

## What Changes

- **A setting, `tabStripDoubleClick`**, with three values: *expand or collapse
  the editor* (the default, what the maximise button does), *new local scratch*
  (what the strip does today), *new global scratch*. In the settings page's
  editor section, worded as the three things and not as their identifiers.
- **The strip asks the setting** on a double-click over its empty part and
  does that one thing; a double-click over a tab is unchanged.
- **The default changes what today's build does.** Somebody who has been
  double-clicking for a scratch finds the editor expanding instead, once, and
  the setting beside it; the release note says so.

## Capabilities

### Modified Capabilities

- `editor`: what a double-click on the tab strip's empty part does, and that
  it is chosen.

## Impact

- **AbydosKit**: `Settings`, one key with three values and a registered
  default.
- **AbydosApp**: `EditorTabBar+Mouse.swift`, the one line; `EditorViewController+Tabs.swift`,
  a third callback for the global scratch; `SettingsPage`, the pop-up.
- **Driving**: `--tab-double` already exists for a double-click on the strip;
  it gains the setting's three values and prints what happened.
