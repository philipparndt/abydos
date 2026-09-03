## Context

The main window is `.titled, .closable, .miniaturizable, .resizable,
.fullSizeContentView` with `titlebarAppearsTransparent`, and the title bar's
contents are this app's own views. Its frame is restored with
`setFrameAutosaveName(Self.mainWindowLayoutName)` for an ordinary run, and with
`setFrameUsingName` for a driven one so that a test never writes somebody's
layout — 0522.

`zoom:` is what a double-click on a title bar sends, under the system setting
that says so. AppKit decides where to zoom to: it asks the delegate for
`windowWillUseStandardFrame(_:defaultFrame:)`, and where the delegate does not
answer, computes a standard frame itself from the window's content and its
resize increments. It then treats the gesture as a toggle: from the standard
frame it restores the *user frame*, the one recorded before the last zoom.

This app answers neither `windowWillUseStandardFrame` nor `windowShouldZoom`.

## Goals / Non-Goals

**Goals:**

- A zoom that stays, every time, whatever the window's history in this run.
- The zoomed size decided here rather than inferred.
- The mechanism named: "sometimes" plus "and then it works" is a state, and an
  unnamed one comes back.

**Non-Goals:**

- Full screen. The report says "full screen" for what a zoom looks like on a
  large display; this is `zoom:`, not `toggleFullScreen:`, and the two are
  different gestures with different keys.
- Changing what is remembered between sittings. The autosave is wanted.
- The torn-off terminal windows, unless the diagnosis says the cause is shared —
  in which case that is the finding and the scope grows on evidence.

## Decisions

**Reproduce before fixing, as with the backlog pane.** That report also carried
the word *sometimes*, and reading gave a plausible ordering that turned out to
be wrong: the real cause was two predicates for one height. A frame that springs
back has at least three candidate mechanisms and they are told apart by
measurement, not by argument:

1. The zoom is *vetoed* after the fact by something restoring the autosaved
   frame — which reading has not found, but reading found nothing for the
   backlog pane either.
2. AppKit's own toggle: the window is already at what AppKit considers the
   standard frame, so the gesture is an *un*-zoom back to the user frame. This
   fits the report best — a window restored from the autosave has no user frame
   that anybody set, and moving it once gives it one.
3. The standard frame AppKit computes for a `fullSizeContentView` window with a
   custom title bar is close enough to the current frame that the zoom looks
   like a flicker.

The first task tells these apart: the frame before the gesture, immediately
after, and a beat later, with `isZoomed` beside each. One of the three shapes
will be in that report.

**The standard frame is ours.** Whatever the diagnosis, the zoom target should
not be a guess about a window whose title bar is not AppKit's.
`windowWillUseStandardFrame` returns the screen's visible frame, which is what a
person means by zooming an editor: as much of the screen as the window may have.

*Ruled out for now: implementing `windowShouldZoom` to force `true`.* It would
suppress a veto without finding out whether there is one, which is the plausible
fix that appears to work.

*Ruled out: dropping the autosave.* The window coming back where it was left is
wanted, and 0522's carve-out for driven runs depends on it.

## Risks / Trade-offs

**The visible frame is the whole screen, and somebody may want a zoom that fits
the content** → An editor is not a document window with a natural width; the
screen is the honest answer, and it is what the gesture does in every editor
people use beside this one.

**Two displays** → `window.screen` is the display the window is on, and its
`visibleFrame` excludes that display's menu bar and Dock. A window dragged
between displays zooms to whichever it is on.

**It may not reproduce** → Then the change fixes the unstated zoom target, says
in this design that the springback was not reproduced and what was ruled out,
and does not claim the report closed.

## Open Questions

- Which of the three mechanisms it is. Unanswered, and the first task.
- Whether torn-off terminal windows share it. Asked once the main window's
  answer is known.
