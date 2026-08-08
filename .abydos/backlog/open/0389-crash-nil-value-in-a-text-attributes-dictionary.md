# 389. Crash: a nil value in a text attributes dictionary

SIGABRT, report `Abydos-2026-08-07-142800.ips`, from the installed build.

Backtrace, main thread:

    -[NSAttributedString(NSStringDrawing) size]
    __NSStringDrawingEngine -> NSCoreTypesetter -> CTLineCreateWithAttributedString
    TTypesetterAttrString::Initialize -> TAttributes::TAttributes -> TAttributes::ApplyFont
    -[NSDictionary initWithDictionary:copyItems:]
    -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]   <- nil from objects[0]

Called from inside a `Task` closure. The two Abydos frames symbolicate to
MainWindowController by nearest exported symbol only, so they name the file
and not the function.

The user's own note: it happens while resizing the git panels.

Ruled out empirically — none of these aborts, probed 2026-08-07:

- an `Optional.none` coerced to `Any`
- a font size of 0, a negative size, NaN
- a cascade list naming absent families
- a Swift struct, class or closure as an attribute value

And by reading: `uiScale`/`activeScale` clamp NaN away, and there is no
`as Any`, `NSColor(named:)` or custom attribute key anywhere in the source.

**It happened again on 2026-08-08 at 14:20:53, and this time the app's own
handler caught it** — so the note above about it never reaching
`~/Library/Logs/Abydos/crash.log` is wrong, and the log is where to look. That
copy is symbolicated, which the crash report is not: the report names
`MainWindowController.showConfigurationMenu` and `stopDevPodForwards`, and both
are wrong — nearest exported symbol, no more.

**The real site is `CommitFileRowView.draw`** (`Sources/AbydosApp/Git/
HistoryPane.swift:768`), inside `NSAttributedString.size()`. That is a file row
under a commit in the history pane, which fits the earlier note about resizing
the git panels: a resize redraws every row.

That view builds three attributed strings, each with two attributes — a font
and a foreground colour. Which narrows it usefully:

- Every colour in the palette comes from `NSColor.hex`, so an sRGB
  `NSCalibratedRGBColor`. Its `copy` is itself; it cannot be the nil.
- Both fonts come from AppKit's own `systemFont(ofSize:weight:)` and
  `monospacedSystemFont(ofSize:weight:)`, non-optional and non-nil, or the
  unwrap would have trapped at the call instead.

So the nil is probably not a value this app put in the dictionary at all: it is
the font `TAttributes::ApplyFont` resolved from ours and inserted, which is what
`objects[0]` is in that frame.

Also ruled out, since it was the obvious next guess: an absurd font size. Both
`uiScale` and `presentationScale` clamp to `zoomSteps` — 0.75 to 2.0 — so the
sizes reachable here are 7.5 to 23.

What is left, and unchecked: `Theme.current` is a `static var` holding a struct
of some thirty-five `NSColor`s, in a target built in Swift 5 language mode, so
nothing has ever complained about who reads it. Assigning a new palette is not
one store, and a reader that catches it mid-assignment gets a torn struct — a
field belonging to neither palette. That would look exactly like this: rare,
unreproducible by probing the values directly, and impossible to see in the
source at the crash site. It also fits the earlier report arriving from inside a
`Task`, where the read would not have been on the main thread at all. Worth
finding out whether anything reads `Theme.current` off the main thread, and
whether anything writes it there.

---

Numbered 42 while it was being worked on, which is what a
commit message citing it means.
