## Context

The bottom panel sits in a horizontal `NSSplitView` (`verticalSplitView`,
`MainWindowController+Layout.swift:220`) whose divider is one point thick
(`ThinDividerSplitView`, `WindowViewHelpers.swift:92`). Its height is points,
not a fraction, and nothing about the terminal's cell size depends on the
pane's width — measured, since a proportional height or a width-dependent cell
would each have explained the report and neither is there.

What is there is `PanelRowSnap` (`Sources/AbydosKit/Project/PanelRowSnap.swift`),
which rounds the panel down so the terminal shows whole rows, asked from
`splitViewDidResizeSubviews` (`MainWindowController.swift:901`) and answered a
turn later.

## Goals / Non-Goals

**Goals:**

- A width-only resize leaves the panel's height alone.
- The snap is a fixed point: applying it once ends it.
- The three other divider computations stop losing a point.

**Non-Goals:**

- The snap itself stays. Whole rows are why the terminal does not draw a strip
  of a row against the top of its viewport, and the decision to trade an exact
  divider position for that is not reopened here.
- No change to what a drag feels like, no animation, no new setting.
- Not the horizontal column split inside the panel, which is proportional on
  purpose: two side-by-side terminals share a width, and that is a different
  question from how tall the panel is.

## Decisions

### The thickness belongs in the arithmetic, not in the caller

`dividerPosition` is the one place that knows what height is wanted, so it is
the place that has to know what `setPosition` will do with its answer. The
thickness comes in as part of `State` rather than as a constant in the kit: the
kit cannot see the split view, and a `ThinDividerSplitView` is a decision the
app makes and could unmake.

Ruled out: subtracting one at each call site. There are four of them, they
already disagreed by exactly this, and the next one would too.

### A width-only resize is filtered by remembering the height

The handler keeps the split height and the panel height it last acted on and
returns early when neither moved. Cheap, obvious, and it stops the reported
symptom on its own — which is worth having even with the arithmetic fixed,
because a `didResizeSubviews` storm during a drag has no business starting a
layout pass per notification.

Ruled out: comparing against the notification's `NSSplitViewOldSize`
userInfo — it is not documented to be there for this notification, and a fix
that depends on an undocumented key is a fix that fails silently later.

### Idempotence is the test, not the arithmetic

The existing test asserts `1000 − 257 = 743`, which is the bug written down as
an expectation. The replacement asserts the property instead: feed the state
the snap produces back into it and get nil. A property test survives the next
change to the arithmetic; an arithmetic test only records what somebody typed.

## Risks / Trade-offs

- [One point of the panel goes to the divider now] → that is where it was
  always going; the difference is that the panel is now told the truth about it.
- [The remembered height could go stale] → it is only an early return; when the
  height does move, the snap runs exactly as before.
- [A drag that changes width and height together] → the height moved, so the
  snap runs, which is correct: a diagonal drag is a height change.

## Open Questions

- None.
