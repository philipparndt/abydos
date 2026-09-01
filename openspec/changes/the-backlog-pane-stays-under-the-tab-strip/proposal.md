## Why

The backlog pane sometimes draws its own toolbar — the `List` / `Board` control
and `Refresh` — on top of the panel's tab strip, so `List` sits under `tmux` and
`Refresh` under the strip's trailing controls. Reported on 2026-09-01 with a
screenshot; the word in the report is **sometimes**, which is the important part
of it.

The mechanism is not diagnosed, and this says so rather than guessing. What is
known from reading: the pane pins its header to its own `topAnchor` and gives it
a height of `Theme.current.scaled(34)`, which is ordinary and would not overlap
anything — so the pane is being *placed* over the strip rather than drawing
outside itself. An intermittent placement fault points at layout order: a pane
installed before the strip has its height, or a top inset applied to the panel
after the pane has been laid out.

There is no originating `.abydos/backlog` item: this comes from a direct report,
2026-09-01, with a screenshot.

## What Changes

- The backlog pane is laid out below the panel's tab strip, every time it is
  shown, whatever order the two are sized in.
- Whatever the cause turns out to be, it is written down: an intermittent
  layout fault that is fixed without being named comes back under a different
  pane.

## Capabilities

### Modified Capabilities

- `backlog`: gains a requirement that the pane's own header is below the strip
  that names it. Nothing existing states where the pane is drawn.

## Impact

- **AbydosApp**: `BacklogPane`'s header constraints, and whichever of
  `BottomPanel`'s install paths sizes a pane — the panel is the only thing that
  can place a pane over its own strip.
- **Risk**: an intermittent fault is one a driven run may not reproduce on
  demand. If it cannot be reproduced, the change says so and fixes the ordering
  that can be shown to be wrong rather than claiming the report is closed.
