## Why

The maintainer, 2026-09-11, with a screenshot of the pull-request list while
it loads: a rounded box in the middle of an empty pane, the system spinner in
it, *Asking GitHub…* under that. *"I don't like this overlay and want
something cooler."* Shown five treatments on 2026-09-12, the maintainer chose
the hairline sweeping under the header, *"as this works best when there is
already text in the panel"* — a refresh with rows on screen is the case the
box handles worst, since it covers the very rows being refreshed — and asked
for two more things: that it be a general feature of every pane, git and
project alike, and that the project pane gain a refresh button.

The box is `PaneActivityView` (`Git/PaneActivityView.swift`), installed over
the whole pane by seven callers — the changes, branches, history and
pull-request panes, the estate overview, the pull-request page and the
sidebar's tool switch — and torn down when the answer lands. The project tree
has no such thing: it reads the folder, sweeps git status and walks the
dependencies on opening, and shows nothing while it does. Neither does the
Backlog pane, which reads its folder off the main thread.

## What Changes

- **A hairline, not a box.** `PaneActivityView` stops covering the pane and
  draws a two-point strip at the seam under the pane's header, with a short
  run of the accent colour sweeping along it while the wait lasts. Nothing is
  dimmed, nothing framed, and rows already on screen stay on screen.
- **The sentence, where there is room.** A pane with nothing beneath the
  strip says what it is waiting for, small and centred — *Asking GitHub…* —
  and past five seconds adds *still waiting*. A pane with rows beneath says
  nothing but the sweep.
- **Every pane, one seam each.** The seven callers keep their calls and give
  the view the header the strip sits under; the project tree and the Backlog
  pane, which never showed a wait, start showing one. The determinate form
  for the estate sweep is the same strip filling from the left.
- **The previews too.** A Cadova model building and a diagram being drawn
  showed the system spinner above their sentence; the strip at the pane's top
  edge is what turns now, and the sentence stays centred on its own. A rerun
  over a model or a picture still on screen shows the strip alone.
- **A refresh button on the project tree's header**, beside the three it
  has, which re-reads the folder and the working copy's status — what a
  build writing files does to the tree, on demand — and shows the strip
  while it does.

## Capabilities

### Modified Capabilities

- `pull-requests`: what the list shows while GitHub is being asked.
- `project-view`: the tree's header gains a refresh, and the tree says when
  it is reading.
- `previews` and `diagrams`: the turning indicator above a preview's sentence
  is the strip at the pane's top edge.

## Impact

- **AbydosApp**: `Git/PaneActivityView.swift` (the drawing and the seam),
  its seven callers (one argument each), `Navigator/NavigatorHeaderView.swift`
  and `ProjectNavigator+Loading.swift` (the button and the tree's waits),
  `Panel/BacklogPane.swift` (its read), `Editor/CadovaPreviewView.swift` and
  `Editor/DiagramPaneView.swift` (their spinner).
- **Driving**: a switch that holds the strip up so it can be captured, and a
  report of where it sits; captures at 1.0 and 2.0 of the list and the tree.
