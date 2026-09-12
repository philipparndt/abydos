## Context

`PaneActivityView` is an `NSView` pinned over the whole pane: an
`NSProgressIndicator`, a caption at `uiFont(11)`, both laid out by hand
against `visibleRect` in the middle, and a rounded panel at 0.92 alpha with a
separator stroke drawn around them. Seven places install it with
`install(over:message:)` and tear it down with `finish()`; the estate sweep
turns it into a determinate bar with `count(_:of:saying:)`. It is scale-aware
whenever it lays out, so the zoom is not the complaint; the look is, and so is
what it does to a pane that already has rows: a refresh of the pull-request
list covers the list.

Five treatments were mocked on 2026-09-12 — the line where the first row
lands, the hairline, the refresh glyph turning, ghost rows, the rail's glyph
breathing — and the hairline was chosen, for the pane that is not empty.

The project tree waits without saying so. Opening a project reads the folder,
sweeps `git status` (`refreshGitStatus`), and walks the dependencies
(`isReadingDependencies`); a large repository shows an empty or stale tree
for the length of it. The Backlog pane reads its folder off the main thread
and shows the previous board meanwhile.

## Decisions

### 1. A strip at the seam, drawn by the same view

`PaneActivityView` keeps its name, its callers and its three verbs — install,
count, finish — and changes what it draws: a two-point strip across the
pane's width, at the seam under the pane's header, with a run of the accent
colour a third of the width long sweeping left to right on a 1.4 s ease. The
panel, the stroke and the system spinner go.

The seam is the header's bottom edge. `install(over:message:below:)` takes
the header view; the strip's y is that view's bottom in the pane's
coordinates, re-read in `layout()` so a header that grows with the zoom moves
the strip with it. A pane with no header — the sidebar's tool switch, the
pull-request page — passes nothing and the strip sits at the pane's top edge.

*Ruled out: the line where the first row would land.* Right for an empty
pane, wrong for a refresh: it displaces the rows it is about to replace.

*Ruled out: a strip drawn by each pane.* Seven drawings of one thing, and the
ninth pane would draw it an eighth way.

### 2. The sentence only where there is room

The caption is drawn small and centred in the space under the strip when the
caller says the pane is empty beneath — `install(over:message:below:paneIsEmpty:)`,
which the pull-request list answers from its rows and the tree from whether
it has a root yet. With rows beneath, the sweep alone says it. Past five
seconds an empty pane's sentence gains *· still waiting* on a timer the view
owns and cancels in `finish()`; a pane with rows has nowhere to say it and
does not.

### 3. The determinate form is the same strip filling

`count(_:of:saying:)` stops sweeping and fills the strip from the left to
`done / total` of the width, with the sentence beneath when the pane is
empty. The estate overview, which is the only caller, gets the same look as
the others at no cost.

### 4. Every pane that waits, and the two that never said so

The seven callers gain the `below:` argument — the changes pane's toolbar,
the branches pane's header, the history pane's header, the pull-request
list's head stack, the estate overview's header, and nothing for the page and
the tool switch. Two panes start waiting visibly:

- **The project tree** installs the strip under `NavigatorHeaderView` while
  it loads a project and while `refreshGitStatus` and the dependency walk
  run after a reload; the watcher's per-event status reads do not show it,
  since a build writing files would keep the strip sweeping all afternoon.
- **The Backlog pane** installs it under its header while `reload()` is off
  the main thread.

The Structure and Scratches panes read nothing asynchronously and show
nothing.

### 5. The previews: the strip is the indicator

`CadovaPreviewView` and `DiagramPaneView` each kept an `NSProgressIndicator`
above their sentence in a stack, placed so that no length of sentence could
put the two on top of each other — the arrangement items 0511 and 0512 were
about. The indicator leaves the stack and the strip at the pane's top edge
turns instead; the sentence is centred on its own, which is the arrangement
those items wanted for the state with nothing turning, and is now the only
arrangement. A preview has no header, so the seam is the top edge. A rerun
over a model or a picture still on screen shows the strip alone: the build's
chatter over the model was never something anybody asked to read, and the
diagram pane already hid its sentence under a picture.

`spin(_:)` keeps its name and its callers in both panes; what it does is
install and finish the strip. The driven reports say `strip=` where they said
`spinner=`.

### 6. A refresh button on the project tree

`NavigatorHeaderView` gains a fourth button, `arrow.clockwise`, after the
three it has, with the tip *Re-read the project*. It calls `reloadTree()` and
`refreshGitStatus()` — the two the driver's `reload` step already calls —
and the strip shows under the header until both have answered.

### 7. Driving

`--hold-activity` keeps every strip up by making `finish()` defer until the
run ends, so a wait that lasts a tenth of a second can be captured. An
`activity` report — `ACTIVITY <pane>: strip y=<pt> height=<pt> sweeping|filled=<n>/<m> saying=<text or nothing>` — is printed by the tree's `activity`
step and the sidebar's, so the seam can be checked against the header's
bottom in numbers rather than by eye.

## What was measured, 2026-09-12

Window captures on the scratch checkout with `--hold-activity`, so a wait of
a tenth of a second stays on screen, and the `activity` tree step printing
every strip: which pane, where it sits, what it sits under, and what it says.

| Run | `ACTIVITY` line |
| --- | --- |
| `--sidebar pull-requests` | `PullRequestsPane: strip y=35 height=3 width=260 under=NSStackView sweeping saying=Asking GitHub…` |
| the same after three zoom-ins | `PullRequestsPane: strip y=50 height=4 width=362 under=NSStackView sweeping saying=Asking GitHub…` |
| the tree, opening | `ColoredView: strip y=94 height=3 width=260 under=NavigatorHeaderView sweeping saying=nothing` |
| `--backlog board` | `BacklogPane: strip y=43 height=3 width=1230 under=NSStackView sweeping saying=nothing` |
| `--file flow.mmd` | `MermaidPreviewView: strip y=0 height=3 width=483 under=top sweeping saying=nothing` |

The strip's `y` is the header's bottom in each pane and moves with it at the
zoom — 35 to 50 under the pull-request switch — and the preview's is its top
edge, as decision 5 says. The sentence is drawn only where the pane was empty
beneath: the list says *Asking GitHub…*, the tree, the board and the preview
say nothing, since rows, columns and a picture are already there. In the
captures the run of colour is visible under the switch, at the Backlog
header's seam, along the preview's top edge, and under *Project*.

**Found by the tree's first capture, and fixed.** The strip reported `y=42`
under the tree's header and was not in the picture: the tree installs its
strip as the project loads, before the header has been given a height, and
the strip's frame was computed in one `layout()` and never again — 42 was a
zero-height header's bottom, which is its top, under the titlebar. The seam
is now read at every draw and every frame of the sweep, one rectangle
conversion each, and the second capture reported 94 and showed the run.

**Not measured.** A list *with* rows being refreshed wants a repository with a
GitHub remote and a signed-in `gh`, which this machine's `gh` is not for
github.com — the same gap the zoom change recorded on 2026-09-03. The code
path is the same `install` with `paneIsEmpty: false`, which the Backlog
capture exercises. The *still waiting* addition is a five-second timer on the
sentence and was not held for; a held strip keeps its sentence as installed.

**Seen on the way.** With the hold on, a pane that reloads twice while
opening installed a second strip under the first — the Backlog pane does —
so a held strip is replaced when its pane installs another. And the
pull-request list's trouble sentence lands beneath the held *Asking
GitHub…*, which no unheld run shows: the strip finishes before the reply is
drawn.

## Release note

> **Waiting is a hairline, not a box.** A pane asking GitHub or git for its
> rows shows a thin sweep of colour under its header while it waits, and says
> what it is waiting for only where there is room to. Rows already on screen
> stay where they are. Every pane has it now, the project tree included, which
> also gains a refresh button beside its other three.

## Open Questions

None.
