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

## What the instrument found, 2026-09-03

**The app's zoom is correct, and the springback was not reproduced.** Five
states, both gestures, both displays: a fresh window, a window restored from
the frame the real app has remembered (`349 979 1280 820 0 0 1920 1050`, whose
top is off a 1050-tall screen and is therefore constrained on restore), a
window sized first, the panel maximised, and the toggle twice. Every one zoomed
to the display's visible frame and stayed there; every un-zoom returned the
window to the size it had and stayed there.

So of the three mechanisms the design listed: the veto is ruled out by reading
(nothing in this app sets the main window's frame outside the driven helpers),
AppKit's own toggle is ruled out by measurement (it toggles cleanly from a
restored frame, from a set frame, and on either display), and a standard frame
too close to the current one is ruled out by the numbers (1280×820 against
1920×985).

**Stating the standard frame made it worse, and that is the finding.** Task 2.1
was implemented — `windowWillUseStandardFrame` returning the visible frame of
the window's own screen — and with it in place a zoomed window could no longer
be un-zoomed: the un-zoom happened and the window returned to the zoomed frame
a beat later. It was reported from the outside within minutes of the build
existing. It is reverted. The lesson is the one the change was written around:
AppKit's guess here was already the visible frame, so the "fix" replaced a
correct answer with the same answer *and* took over a decision AppKit uses to
compute `isZoomed`, which is what the un-zoom depends on.

**And the instrument told the same lie first.** `doubleClickTitleBar` began by
queueing the release and then sending the press, which is what `TreeKeys` must
do for a table's tracking loop. A title bar runs no such loop, so the release
arrived on a later turn with no press in front of it and AppKit read an up
carrying `clickCount: 2` as a double-click of its own — every gesture zoomed
twice, and an un-zoom sprang back. That is *exactly* the reported symptom,
produced entirely by the measuring apparatus, and it is why the API path is
driven beside the click: the two disagreeing is what caught it.

**Where that leaves the report.** Unreproduced, and this change is not closed.
What is known now: it is not the frame arithmetic, not a veto, and not the zoom
target. What is untried: a window that has lived through display changes, sleep
or a full-screen space — the state the reporter's window had and a fresh process
cannot have. The next person has the instrument.
