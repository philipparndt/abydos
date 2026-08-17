## Why

SIGABRT in the installed build, twice — report `Abydos-2026-08-07-142800.ips`, and
again on 2026-08-08 at 14:20:53, that time caught by the app's own handler. The
second copy is symbolicated and the crash report is not, which matters: the report
names `MainWindowController.showConfigurationMenu` and `stopDevPodForwards` and
**both are wrong**, nearest exported symbol and no more.

The real site is `CommitFileRowView.draw`
(`Sources/AbydosApp/Git/HistoryPane.swift:768`), inside `NSAttributedString.size()`.
A file row under a commit in the history pane — which fits the user's own note that
it happens while resizing the git panels, since a resize redraws every row.

The backtrace ends in `-[__NSPlaceholderDictionary initWithObjects:forKeys:count:]`
with nil from `objects[0]`, reached through `TAttributes::ApplyFont`.

**The nil is probably not a value this app put in the dictionary.** That view builds
three attributed strings, each with a font and a foreground colour. Every colour
comes from `NSColor.hex`, an sRGB `NSCalibratedRGBColor` whose `copy` is itself.
Both fonts come from AppKit's own `systemFont(ofSize:weight:)` and
`monospacedSystemFont(ofSize:weight:)`, non-optional and non-nil or the unwrap would
have trapped at the call. So `objects[0]` is the font `ApplyFont` resolved from ours
and inserted.

**What is left, and unchecked:** `Theme.current` is a `static var` holding a struct of
some thirty-five `NSColor`s, in a target built in Swift 5 language mode, so nothing
has ever complained about who reads it. Assigning a new palette is not one store, and
a reader that catches it mid-assignment gets a **torn struct** — a field belonging to
neither palette. That would look exactly like this: rare, unreproducible by probing
the values directly, and impossible to see in the source at the crash site. It also
fits the first report arriving from inside a `Task`, where the read would not have
been on the main thread at all.

From `.abydos/backlog/waiting/0400-crash-a-nil-value-in-a-text-attributes-dictionary.md`,
previously numbered 42 and 389.

## What Changes

- Establish who reads and writes `Theme.current`, and from which thread. This is the
  unchecked hypothesis and the first work, not an assumption to build a fix on.
- If the palette can be read while it is being assigned, make that impossible —
  publication that a reader cannot catch half of.
- If it cannot, the hypothesis is written down as ruled out with the evidence, and
  the investigation moves to what `ApplyFont` was given.

## Capabilities

### New Capabilities
- `theme-access`: what is guaranteed about reading the current palette — that a
  reader gets one palette or another and never a mixture, and which thread may
  change it.

### Modified Capabilities
<!-- None. -->

## Impact

- `Theme.current` and every reader of it, which is most drawing code in `AbydosApp`.
- `CommitFileRowView.draw` in `Sources/AbydosApp/Git/HistoryPane.swift`, the known
  crash site, but not the cause if the hypothesis holds.
- Theme switching — whatever assigns a new palette, including any appearance-change
  observer that may not be on the main thread.
- The app's own crash handler and `~/Library/Logs/Abydos/crash.log`, which is where a
  symbolicated copy lands and is where to look. An earlier note in the item claiming
  it never reaches there is wrong.
