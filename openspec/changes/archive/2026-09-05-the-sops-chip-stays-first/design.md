## Context

`EditorStatusView` — the one status bar for the whole editor area, at the foot
of `EditorViewController.swift` — draws its chips by hand in `draw(_:)`. The
right side is language, position, and the server chip in whatever room is
left. The left side is `drawLock()` then `drawSops()`, and that order is the
fault: the lock stands at `scaled(12)` from the edge whenever the file
conceals, and `drawSops` computes its own origin as "after the lock when there
is one, at the edge when there is not". Both chips' hit-testing, hover and
tooltips already work off the rectangles (`sopsRect`, `lockRect`) and would
follow either order unchanged.

The states that matter: a SOPS file arrives encrypted and conceals nothing, so
the chip is alone at the edge; the decrypt reveals the file's values, which
brings the lock up open beside it, and the chip — just pressed — hops to the
right of the lock it caused.

## Goals / Non-Goals

**Goals:**

- The SOPS chip's left edge is the same place — the bar's left edge plus the
  standing margin — in every state and on every redraw, whether the lock is
  shown or not.
- The lock, when shown, stands to the chip's right with the one gap the bar
  already uses between chips, and is alone at the edge for files that conceal
  but are not SOPS's (a `.env` with no chip).

**Non-Goals:**

- Nothing about what either control *does*: the decrypt, the encrypt-and-save,
  the covers and the tooltips are all as the sops change left them.
- No fixed-width slot for the chip. The chip's text changes width with its
  state — *SOPS · encrypted* is narrower than *SOPS · encrypt and save* — and
  the lock follows the chip's tail, so the lock still moves when the chip's
  words grow. Only the chip's origin is pinned; a bar that reflows is what a
  status bar is.

## Decisions

### The chip is drawn first and at the edge; the lock follows it

`draw(_:)` calls `drawSops()` before `drawLock()`; `drawSops` takes its origin
from the edge alone, dropping its `lockRect` dependency; `drawLock` takes its
origin from `sopsRect` — at the edge when there is no chip, after its tail
plus the standing gap when there is. The two `chipRect`-driven rectangles
already carry everything downstream: `mouseMoved`, `mouseDown`,
`resetCursorRects` and `refreshServerToolTip` read them and are untouched.

*Ruled out:* keeping the lock first and reserving a slot beside it for the
chip. The reservation wide enough for the longest label is mostly empty in
most states, and it asks the eye to look past a gap to find the chip — a
second-order fix for the wrong slot.

*Ruled out:* moving both to the right side. The left is where the bar keeps
the file's own facts by design — the lock's drawing comment says so, "where
the eye already checks the file's facts" — and the right side's order is
already spoken for: the server is the one allowed to lose room there.

*Ruled out:* teaching the driven report to name chip rectangles. The report
says state, line count and digest, deliberately; a position claim belongs to
a picture, not to a report, and the driven screenshot is the proof this
project uses for chrome.

### The proof is the pair of screenshots the report came with

The driven run from the sops change — scratch project, `age` key, real `sops`
— already decrypts in place; its capture of the bar is retaken for both
states. The claim each picture makes: the chip's left edge is the same pixels
in *SOPS · encrypted* standing alone and in *SOPS · decrypted* with the lock
beside it.

## Risks / Trade-offs

- [The lock now moves when the chip's words grow — *decrypted* becoming
  *encrypt and save* on an edit] → accepted and said above: the chip is the
  button and keeps its origin; the lock is a fact beside it and follows, the
  same way the server chip follows the position's width. The lock is pressed
  far less often than the chip it used to displace.
- [A very long server name meets the lock at a narrow window width] → no
  worse than today: the server truncates in the room the left chips leave,
  and the left side gains nothing in this change — the pair's total width is
  the same, only swapped.
- [`Scripts/file-size-allowed.txt`] → `EditorViewController.swift` sits at its
  raised ceiling; this change moves lines within `EditorStatusView` and adds
  none, so the ceiling should hold — checked in the finishing task rather
  than assumed.
