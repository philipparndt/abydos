## Context

This is a diagnosis with one candidate left, not a fix waiting to be typed. What has
already been eliminated is worth keeping in front of whoever picks it up, because
re-eliminating it is the obvious way to spend a day.

**Ruled out empirically — none of these aborts, probed 2026-08-07:**

- an `Optional.none` coerced to `Any`
- a font size of 0, a negative size, NaN
- a cascade list naming absent families
- a Swift struct, class or closure as an attribute value

**Ruled out by reading:** `uiScale`/`activeScale` clamp NaN away, and there is no
`as Any`, `NSColor(named:)` or custom attribute key anywhere in the source.

**Ruled out later, since it was the obvious next guess:** an absurd font size. Both
`uiScale` and `presentationScale` clamp to `zoomSteps` — 0.75 to 2.0 — so the sizes
reachable at that site are 7.5 to 23.

What remains is the torn read of `Theme.current`. It has the right signature for the
evidence: rare, unreproducible by probing values directly, invisible in the source at
the crash site, and consistent with the first report arriving from inside a `Task`.

## Goals / Non-Goals

**Goals:**

- Find out whether anything reads `Theme.current` off the main thread, and whether
  anything writes it there. That is the whole first phase.
- Make a palette read atomic with respect to a palette change, if it is not already.
- Leave the evidence behind either way, so the next report does not restart here.

**Non-Goals:**

- A general audit of concurrency in `AbydosApp`. One `static var` with a known
  crash attached to it.
- Moving the target off Swift 5 language mode. Strict concurrency checking would
  surface this class, and that is a much larger change with its own argument; if the
  investigation makes the case for it, that is a proposal of its own.

## Decisions

**Prove the hypothesis before fixing it.** A crash reproduced twice in a year cannot
be confirmed fixed by not crashing. So the phases are: establish the access pattern
statically, then make a change whose correctness is arguable from the code rather
than from the absence of a report.

**If the palette must be read off the main thread, publish it atomically.** A struct
of thirty-five `NSColor`s is not one store, and the fix is to make readers take a
reference to an immutable value rather than reading fields out of a mutable struct
— assign a whole boxed palette, so a reader holds the old one or the new one.
Candidates, to be chosen when the access pattern is known:

- A class holding the palette, assigned as one reference.
- `@MainActor` on `Theme.current`, if every reader turns out to be main-thread
  already — the strongest option, because it makes the wrong access a compile error
  rather than a rarity. The Swift 5 language mode is why nothing has complained.

**Prefer confining to serialising.** A lock around every colour read is a cost on
drawing code — this is an editor, and the palette is read per row of a table. If the
readers are all main-thread but for one, moving that one is cheaper and more honest
than making everyone pay for it.

**If the hypothesis fails, say so in the item and stop.** A wrong diagnosis written
down with its evidence is worth more than a speculative fix, because the next report
will arrive with the same backtrace and somebody will otherwise start here again.

## Risks / Trade-offs

- **The change cannot be verified by reproduction** → Accepted, and it is the reason
  for the static-proof-first ordering. A test can assert that a reader observes a
  whole palette after a switch; it cannot assert that the crash is gone.
- **`@MainActor` propagating further than expected** → Likely, in a target that has
  never been checked. If it spreads, that is information about the real access
  pattern and belongs in the item.
- **Fixing the wrong thing** → The four eliminations above are why this candidate is
  the one being pursued. If the access pattern turns out to be clean, that is a
  result and the item goes back to waiting rather than a fix being invented.

## Open Questions

- Does anything read `Theme.current` off the main thread today?
- Does anything write it off the main thread — an appearance-change observer, say?
- Which `Task` was on the stack in the first report? The frames symbolicate to
  `MainWindowController` by nearest exported symbol only, so it is not known.
