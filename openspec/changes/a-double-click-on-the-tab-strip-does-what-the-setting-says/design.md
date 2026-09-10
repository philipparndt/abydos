## Context

The editor's header is `EditorTabBar`, and a double-click on the empty part of
it is one line in `EditorTabBar+Mouse.swift`:

    if event.clickCount == 2 { onNewScratch?() }

with a comment that this is what the editors people arrive from do. It is what
one family of them does; in the other the same gesture maximises the editor,
which this strip already offers as a button (`maximizeButtonFrame` →
`onMaximize` → `toggleEditorMaximized`) and which the maintainer reaches for.
The strip's own context menu already knows both scratches — `onNewScratch` and
`onNewGlobalScratch`, the second reaching `newScratch(global: true)` in
`EditorViewController+Opening.swift` — so the three things the setting names
all exist; only the gesture is hard-wired.

## Decisions

### 1. One setting, three values, worded as what they do

`Settings.tabStripDoubleClick`, a string key with a registered default, read
through an enum in the Kit:

    public enum TabStripDoubleClick: String, CaseIterable { case maximize, localScratch, globalScratch }

`maximize` is the default. The settings page's *Editor* rows gain a `.choice`
titled *Double-click on the tab strip* whose options read *Expand or collapse
the editor*, *New scratch file in this project* and *New global scratch file*
— the three things, not the three identifiers — with help saying where the
other two are still reachable (the strip's menu and the maximise button).

*Ruled out: a modifier instead of a setting* — ⌥-double-click for the other
thing. Two gestures nobody can discover replace one setting somebody can read,
and the report asked for a setting.

### 2. The strip asks, and does one thing

`EditorTabBar+Mouse.swift` gains a third callback beside the two scratches, or
rather uses the two it has: on a double-click over the empty part the strip
reads the setting and calls `onMaximize`, `onNewScratch` or
`onNewGlobalScratch`. The decision is the strip's, in one `switch`, so a test
of the mapping is a test of the strip and not of a controller three layers up.
A double-click *on a tab* is unchanged — it makes a preview tab permanent — and
the maximise button is unchanged.

### 3. The default changes what today's build does, and the release note says so

Somebody who has double-clicked the strip for a scratch will find the editor
expanding instead, once. The setting is beside it and the strip's menu still
makes a scratch in one click. The note names the old behaviour and where it
went, so nobody has to find out by losing a gesture.

### 4. Driving

`--tab-double` takes a tab index today and refuses one that names no tab. It
gains `empty` for the strip's empty part, and prints what happened —
`editorMaximized=` from the window's layout report, or the scratch that opened
— so a run under each of the three values is three lines.

## What was measured

*(the runs, once made)*

## Release note

> **A double-click on the editor's tab strip is yours to choose.** It expands
> and collapses the editor now, as the maximise button beside it does; it used
> to open a scratch file. A setting under *Editor* offers the old behaviour
> back — a scratch in this project — or a global scratch, and the strip's menu
> still makes either in one click.

## Open Questions

None.
