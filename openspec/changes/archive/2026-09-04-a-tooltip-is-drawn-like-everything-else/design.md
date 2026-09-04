## Context

`PanelTabStrip` answers `NSViewToolTipOwner` with a string per control. The
pill's is three sentences; the rest name a verb and a key.

`ParameterHintStrip` is the app's existing floating-panel-with-a-drawn-view:
`[.borderless, .nonactivatingPanel]`, transparent, `.popUpMenu` level,
`ignoresMouseEvents = true`, added as a child of the window it belongs to.

`TitlebarCapsule` and `RunningSessionsPopover` both show a key the same way:
dimmed small text, set apart at the trailing edge, never inside the sentence —
because a key inside a sentence reads as punctuation. Neither draws a cap
around it. A tip has room for the stronger form, so this one draws the cap, and
it is the first place in the app that does.

## Goals / Non-Goals

**Goals:**

- What the controls say is drawn in the theme, with a hierarchy: what this is,
  then what it does, then the key.
- The gesture is unchanged: rest on a control, it appears; leave, it goes.

**Non-Goals:**

- Replacing AppKit's tooltips everywhere. Most of them are one short label,
  which a plain string says perfectly.
- A tooltip that can be clicked, scrolled or selected. It is a sentence you
  read and then stop reading; anything else is a popover and has a gesture of
  its own.
- Following the pointer. It appears where the control is, as AppKit's does.

## Decisions

**A `Tip` value, not a string.** `title`, `detail` and `shortcut` as three
fields, so the drawing decides the hierarchy rather than the caller deciding it
with punctuation. A caller with one short thing to say passes a title and
nothing else, and gets one line.

**One panel per window, shared.** A tooltip is only ever one at a time. Making
one per control would be eight panels on a strip that redraws twice a second
while tmux is watched.

**The delay is the app's, not AppKit's.** `NSView.toolTip` has a system delay
this cannot read, so the strip keeps its own timer. Half a second, which is
what the system's own default measures as, and the timer is cancelled by the
pointer moving to another control — so crossing the strip does not leave a
trail of tips.

*Ruled out: `NSView.toolTip` with an attributed string.* It does not take one.

*Ruled out: keeping AppKit's tooltip and adding the drawn one beside it.* Two
tips for one control, at two delays, in two styles.

**It ignores the mouse.** A tip that can be hovered would keep itself alive
under a pointer that has left the control, which is how a tooltip becomes a
thing to dismiss.

## Risks / Trade-offs

**A tip near the screen's edge** → it is clamped to the window it hangs off,
which is where the control is; a strip control is never at the top of a screen.

**A tip left behind by a window that goes away** → it is a child window, so it
goes with its parent, and the strip hides it on exit, on a press, and when the
strip leaves its window.
