## Context

`PanelTabStrip` draws its tabs and, at the trailing end, the sessions pill, the
`tmux · session` tag, the follow, maximise and hide buttons, the overflow
chevron and the `+` with its own chevron. It already tracks a hovered tab and a
hovered ✕ in `updateHover`, and already answers tooltips as an
`NSViewToolTipOwner` — from the point, because the strip is rebuilt whenever
tmux's windows are re-read and anything remembered by index would name the
wrong tab a moment later.

So both mechanisms existed and neither reached these controls.

## Goals / Non-Goals

**Goals:**

- The pointer says what is under it, everywhere on the strip.
- Each control explains itself where somebody meets it.

**Non-Goals:**

- Labels on the strip. There is no room, and the pill's whole argument is that
  two numbers in the corner of the eye are cheaper than a sentence.
- A tooltip on a tab that has nothing unusual to say. Tabs already answer with
  their engine note when there is one, and a tip that repeats the label under
  it is noise.

## Decisions

**One `TrailingControl` for the hit test, the hover and the words.** The
alternative is a rect comparison at each of the three sites, which is how the
chevron came to be counted, reserved, clickable and never drawn — three places
that had to agree and did not.

**The words live together in one function.** A tooltip is the only place
several of these are ever explained, and read side by side they can be made to
sound like one another. Scattered beside their drawing calls they would drift
in person and tense the way two spellings of one message always do.

**Checked against the pixels.** The hover was verified by cropping the same
region from a run with the pointer on the control and one without, on a glyph
button and on the pill. That is what caught the pill's halo being invisible —
the report would otherwise have been "hover added" with a control that does not
visibly hover, which is the same fault as the chevron in another costume.

**Tooltips re-registered on a change of shape, not on every layout.** Never
would leave a rect where a control used to be, and every time would tear a tip
down while somebody is reading it, twice a second, while tmux is watched.

## Risks / Trade-offs

**A tooltip that names a key that changes** → The keys are in the words, and a
key that moves leaves a tooltip lying. They are stated once each here, and the
menu is the other place they are written; nothing checks that the two agree.
