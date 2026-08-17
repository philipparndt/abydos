# 400. Crash: a nil value in a text attributes dictionary

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

Previously numbered 42, 389.

---

## The torn palette read is ruled out (2026-08-17)

The candidate list is one shorter. `Theme.current` is read on the main thread and
written on the main thread, and nothing was found or observed doing either
anywhere else:

- **Every writer is on the main thread.** Five sites: `applicationDidFinishLaunching`,
  the `AppleInterfaceThemeChangedNotification` observer (queue `.main`, and its
  work deferred through `DispatchQueue.main.asyncAfter`), the launch option that
  sets a theme, the settings-changed handler in `MainWindowController`, and the
  appearance-walk driver verb.
- **No view draws concurrently.** `canDrawConcurrently` appears nowhere, so every
  `draw(_:)` is on the main thread by AppKit's own rule.
- **The one clock that drives drawing is the main one.** The terminal's
  `CADisplayLink` is added with `link.add(to: .main, forMode: .common)`.
- **Every background block in the app target calls only into `AbydosKit`** —
  discovery, `PdfPreview.open`, `ProcessPipes`, rope measurement — and hops back
  through `DispatchQueue.main.async` before touching a view. `AbydosKit` cannot
  see `Theme` at all; it is in `AbydosApp`.
- **The `Task` closures that are not `@MainActor`** — the diagram renderers —
  were read through: they render, they cache, and none of them reads the palette.

Then observed rather than only argued. A debug build now records any read or
write of the palette from another thread, and two driven runs against a
scratchpad project — one with the terminal, the panel and the backlog open, one
switching the appearance five times over while the whole window redrew — both
reported *"palette touched on the main thread only"*.

That check stays in the tree. The audit above is a claim about 1580 reads across
99 files and it is true on the day it was made; the next person to write one of
those will not have read this.

**So the crash is still unexplained, and this is a result rather than a
failure.** What is left of the list: whatever `TAttributes::ApplyFont` resolved
our font to, which is where the nil actually is. `Theme.uiFont` hands AppKit
`.systemFont(ofSize: size * scale, weight:)` and nothing else, and sizes are
clamped to 7.5–23, so the next place to look is what happens to that font
between our call and CoreText — a cascade resolved against a font that has gone
away is the obvious next candidate, and `FontRegistry.registerBundledFonts`
runs before any of this.

Also done while here, so the next report costs less: the crash log now carries
the build, the image's load address, its slide and its UUID. Without those the
addresses in an old log cannot be turned into file and line by any dSYM, because
ASLR moves the image every launch.
