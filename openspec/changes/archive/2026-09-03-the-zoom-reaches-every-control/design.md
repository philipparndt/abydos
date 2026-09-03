## Context

The zoom is one number: `Settings.activeScale`, which is `uiScale` normally and
`presentationScale` while presenting, and every dimension in the app is meant to
pass through `Theme.scaled(_:)` or `Theme.uiFont(_:)` on its way to the screen.
That is true of everything the app paints itself, because those read
`Theme.current` inside `draw(_:)` and so re-read it on every repaint. It is
false of two other kinds of thing:

- **A bezel.** `NSButton` with `.rounded`, `NSSegmentedControl`, `NSSwitch` and
  a checkbox take their size from `controlSize`, which has four values and a
  largest. `DrawnButton`'s own comment carries the measurement: on macOS 27 the
  bezel is 20 points tall at `.small` and 28 at `.large` whatever font is put
  inside it. `.large` walls out at roughly 1.4×, and every one of these controls
  is at `.small`.
- **A number copied at build time.** `commitTable = makeTable(rowHeight:
  Theme.current.scaled(40))` is read once. So is `searchField.font =
  Theme.current.uiFont(12)`, so is `outline.backgroundColor`, and so is every
  constraint constant a pane sets in its initialiser.

Both were survivable while the zoom was rarely touched. Presentation mode made
the zoom something people flip in front of a room, and the reports followed
within a day.

The app does not have one worked answer already. It has **three**, in three
files, none of them shared, and each written the day somebody noticed a control
that would not grow:

- `DrawnButton` (`NSButton`, drawn), for the missing-server strip and the
  toasts — two callers;
- `PillButton` (`NSView`, drawn), for the titlebar;
- `RowAction` / `ActionableRowView`, which is not a control at all but a verb
  painted into a row by the git tree — `Review 3 changes…`, the traffic button,
  the glyph beside it.

The third was pointed at during this change as "the one that works at all zoom
levels", and it does, for the reason all three do: **every dimension is read
from `Theme.current` inside a drawing call**, so it is re-read on the next
repaint and there is nothing stored to go stale. `RowAction`'s own comment gives
the same reason from the other side — an `NSButton` there "would be the one
control in the tree that did not match the rest of it".

Three correct implementations of one idea, in three files, is the argument for
the library rather than against it. The library is not a new answer; it is the
fourth writing of an answer that has been found three times, made shared before
it is found a fourth.

The rest of the app is about seventy bare `NSButton`s, nine
`NSSegmentedControl`s and ten `NSSearchField`s.

## Goals / Non-Goals

**Goals:**

- A control set whose size follows `activeScale` at every one of the nine zoom
  steps, with no wall.
- A control that is correct after a zoom **without its owner remembering to do
  anything**. Having to remember is the fault.
- The panes named in the reports moved onto it: the log page, the commit page,
  the pull-request review page, the pull-request list.
- The commit row tall enough for both its lines at every step, decided by
  arithmetic that is tested rather than by a number that was right once.
- The project tree's palette re-applied on a theme change.

**Non-Goals:**

- The settings window, the sheets, the pickers and the dialogs. They are modal
  or occasional, none of them was reported, and a seventy-site diff is already
  wide. They keep their bezels and are swept separately once the library has
  been used in anger.
- Changing the zoom steps, the presentation scale, or what any control does.
- A general theming language. This is a handful of shapes the app actually
  draws, not a widget toolkit.
- The terminal, which has its own metrics and its own renderer.

## Decisions

**The library draws, and does not bezel.** Every member paints itself in
`draw(_:)` from `Theme.current`, which is what makes it follow the zoom for free
— the same mechanism the three existing drawn controls already prove.

**The rule underneath it, stated once**: a dimension is *read where it is used*,
never stored. That is the whole difference between the controls that work and
the controls that do not, and it is why `DrawnButton` follows the zoom while an
`NSButton` beside it does not — and equally why `commitTable`'s row height does
not follow while the fonts drawn into that row do.

*Ruled out: keeping `NSButton` and raising `controlSize` with the scale.* It
buys a factor of about 1.4 and then stops, which turns a visible fault into one
that only appears past a threshold — worse, because it looks fixed. The
measurement in `DrawnButton` is what kills it.

*Ruled out: an `NSView` transform (`layer.transform` scaling) over stock
controls.* It scales the artwork's pixels rather than laying out at the size, so
text goes soft, hit regions drift from what is drawn, and the focus ring is
scaled too. A control that is blurry in a room is worse than one that is small.

**The three that already work are folded in, not left beside it.**
`DrawnButton` becomes the library's drawn button. `PillButton` and `RowAction`
stay where they are for now — the titlebar and the git tree draw them into
contexts of their own, and moving them is a second change with nothing to gain
in this one — but the library's metrics are the ones they already use, so the
three cannot drift further apart while this is in flight.

*Ruled out: making the library out of `PillButton` because it is an `NSView`
rather than an `NSButton`.* `NSButton` carries the target/action, the
accessibility role and the key loop for free; `PillButton` reimplements the
first and does without the others because the titlebar does not need them. The
library is for controls in panes, which do.

**One observer, not one per control.** A `ScaledControls` registry holds weak
references to live controls, observes `.abydosSettingsChanged` once, and tells
each to re-take its metrics. A control registers itself in `init`.

*Ruled out: each control observing for itself.* Seventy observers on one
notification is not expensive, but the order in which they fire is unspecified,
and a control that dies without removing its observer is the crash this app has
had before. A registry of weak boxes cannot leak an observer and can be asked,
in a driven run, what it currently holds.

*Ruled out: leaving it to each pane's `applySettings()`.* That is what the app
does today, and the seven reports are the panes that forgot. A mechanism whose
correctness depends on remembering is the thing being replaced.

**The search field keeps AppKit's field.** `NSSearchField` carries the field
editor, the cancel button, the search menu and the recents behaviour, and none
of that is worth redrawing to fix a font size. It is wrapped rather than
replaced: the wrapper gives it `Theme.uiFont`, an explicit height constraint
from the theme, and re-gives both on a scale change. Its rounded bezel stretches
to the height it is given, which the drawn controls' does not have to.

This is the one place the library has two kinds of member — **drawn** and
**measured** — and the distinction is stated rather than hidden, because a
future member has to be put in one camp or the other deliberately.

**A row's height is derived from its content, not chosen.** `scaled(40)` was
right at 1× and wrong above it; the fix is not a bigger number. The height comes
from the two lines the row actually draws plus its paddings, and the arithmetic
lives in AbydosKit as a pure function so it can be tested over all nine zoom
steps without a window.

The line heights themselves are **given to it rather than assumed**, the way
`PanelRowSnap` is given the divider thickness: the view measures its own fonts
and hands the numbers in. That keeps AppKit out of the tested part and keeps the
function honest when a font changes.

**The detail area is re-divided, not remembered.** The commit page's detail area
is a split position in points. Coming back from presentation mode, the points
that were right at 1.5× are wrong at 1.0×, and nothing re-asks. It is
recomputed from the scale on a scale change — which is the same class of fault
`PanelRowSnap` was written for, so it is worth checking whether that machinery
covers this split too rather than growing a second copy.

**The project tree's colours are re-applied where its other metrics already
are.** `applySettings()` re-applies the row height and the indentation; the
background and the container's colour join them. The container also gains the
`colourSource` closure that `MainWindowController+Layout` already gives to its
sibling containers — the mechanism exists and this view was missed.

*Ruled out: relying on `ThemeSwap` to catch it.* `ThemeSwap` recognises colours
by value and swaps them, and it walks the window's content view, so in principle
it should already reach the outline. It demonstrably does not, and a fix that
depends on working out why a general mechanism missed one view is a fix that can
regress silently. The explicit re-apply is three lines and cannot.

## Risks / Trade-offs

**Seventy call sites is a wide diff, and a wide diff hides a mistake.** →
The sweep is limited to the four panes in the reports. Each pane is one commit's
worth of change with a driven capture before and after, rather than one commit
that touches everything.

**A drawn control has no system affordance.** A bezel says "press me" in a way a
drawn rectangle has to earn, and it carries focus ring and accessibility
behaviour for free. → The library keeps `NSButton` as its superclass, as
`DrawnButton` already does, so the action, the target, the accessibility role
and the key loop are unchanged; only the drawing is ours. Focus is drawn
explicitly rather than left to the system ring.

**A checkbox drawn by hand can drift from the system's.** `Hide read` and
`Whole file` are checkboxes, and people know what one looks like. → The drawn
box follows the system's proportions at 1× and is compared against a capture; if
it cannot be made to read as a checkbox, those two stay bezelled and the
report's "not scaled" is accepted for them, named in the tasks rather than
quietly dropped.

**The registry holds weak references, and a control removed from a window but
kept by its pane stays registered.** → That is correct: it will be shown again
and has to be right when it is. The registry is swept of nil boxes when it is
walked.

## What the open questions turned out to be

**The commit page's detail area is not `PanelRowSnap`'s fault.** Read before
anything was written, as the task said. That machinery is about rounding a
terminal's height to whole rows and has nothing to say here; the page's own
split is placed as a *fraction* of the width and follows a resize correctly.
What does not follow is the description box, whose height is
`Theme.current.scaled(150)` in a constraint constant — copied once when the pane
was built. Leaving presentation mode put the type back to 1.0× and left the box
at the height 1.5× had asked for. So: no second divider path, and instead the
pane remembers every height it took out of the theme and takes them again.

**The drawn choice keeps the arrow keys**, so the fallback is not needed and
`NSSegmentedControl` is gone from these panes rather than kept as a measured
member. ← and → are answered in `DrawnChoice.keyDown` directly. The reason this
was worth checking rather than assuming: two `DrawnButton`s in a stack view
would have looked identical in a screenshot and lost the behaviour silently.

**Why `ThemeSwap` misses the navigator's outline was not chased**, and this is
the record of that decision rather than a gap. The explicit re-apply is two
lines in the method that was *already* re-applying that view's other metrics
and had simply never been given its colours; chasing a general mechanism to
find out why it missed one view would have been a change of its own, on the
critical path of a release that is being held. It is worth knowing — it may be
missing other views for the same reason — and it is filed as its own question
rather than as part of this.

## Open Questions

- Why `ThemeSwap.apply` does not reach `NavigatorOutlineView.backgroundColor`
  when it walks the window's content view and has an `NSTableView` case that
  should match. Not chased here; see above.

## What the captures found, 2026-09-03

**The hash fits at both zooms**, which was the report, and the row is derived
rather than the constant it was. **At 2.0 the ref tags on a commit run into the
author column**: `feature/beta` on the initial commit overlaps `probe`. The tags
are laid out from the left and the author from the right at widths that meet
at 2.0 in a pane this wide; not this change's fault and not fixed here, but
seen in its capture and worth a change of its own.

**The pull-request pages were not captured.** `gh` on this machine is signed in
to the corporate GitHub only and the repository's forge is github.com, so the
list and the page have nothing to show. The header controls moved onto the
library in 5.1 and 5.2 and the claim is the same as the log page's; the capture
wants a machine signed in to the right forge.

**The detail area is re-divided, and the panel is not.** Toggling presentation
mode on and off with the commit page open: the message area is 74 points at
1.0, 100 while presenting at 1.5, and 74 again afterwards, which is the claim.
The page's whole pane, though, came back 100 points shorter — 326 against 426 —
so something below it remembers a height in points across a change of scale and
hands it back scaled. Most likely the terminal panel's height. Not this change's
control, and a report of its own.
