# 5. Crash: a nil value in a text attributes dictionary

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

Next: the app writes `~/Library/Logs/Abydos/crash.log` for uncaught
exceptions but this never reached it, because the throw goes straight to
`std::terminate` from inside CoreText. Reproducing it by resizing the git
panels under the screenshot harness is the way in.

---

Numbered 42 while it was being worked on, which is what a
commit message citing it means.
