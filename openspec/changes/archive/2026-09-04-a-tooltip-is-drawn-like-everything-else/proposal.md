## Why

Asked for, the day after the strip's controls gained tooltips at all: "the
tooltips are currently plain text, think we can make them nicer".

They are AppKit's, and AppKit's tooltip takes a `String`. So the pill's — which
has to say what two counts mean, that a finished session is in neither, and
which key opens the list — is three sentences of one size, one colour and one
weight, in a yellow box that belongs to no theme in this app. Everything else
here is drawn: the tabs, the pill itself, the rail, the buttons, the running
list. The one thing explaining them is the one thing that is not.

The parts are already in the app. `ParameterHintStrip` is a borderless
non-activating panel holding a drawn view, at `.popUpMenu` level, ignoring the
mouse — the shape a tooltip wants — and `TitlebarCapsule` already draws a key
as a cap rather than as the characters `⇧⌘P`.

## What Changes

- **A drawn tip**, in the theme's own colours: a title line in the text ink, a
  body in the dimmed one, and a shortcut drawn as a key cap rather than
  written into the sentence.
- **The strip's trailing controls use it.** They are what the report is about,
  and what the pill has to say is the reason a plain string was not enough.
- **It appears the way a tooltip appears** — after a pause on the control, gone
  the moment the pointer leaves or anything is pressed — so that nothing about
  the gesture changes, only what it looks like.
- **Nothing else moves.** Every other tooltip in the app stays AppKit's; a
  label on a button is a label, and a drawn panel for one is a panel to
  maintain for nothing.

## Capabilities

### Modified Capabilities

- `terminal`: what the strip's controls say is drawn, with the shortcut as a
  key.

## Impact

- **AbydosApp**: a `StyledTip` in `Controls`, one panel per window shared by
  whatever asks; `PanelTabStrip` hands it a title, a body and a key instead of
  registering a string.
- **Driven**: the existing `--hover-control` prints what the tip holds, so the
  words stay readable from a run rather than only from a screenshot.
