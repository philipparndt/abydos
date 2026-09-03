## Why

The project tree says a file has changed by **colouring its name** and in no
other way. That is a real signal and it is the wrong shape for the question it
answers: a green name is only legible against the names beside it, so a tree
scrolled to a run of untracked files reads as a tree of green text, and a single
modified file among forty unmodified ones is one word in a slightly different
colour. Every other editor puts a mark on the row.

Asked for on 2026-09-01 — "it would be nice to render change dots in the tree,
like vscode does" — and refined to marking the changed **file**, with the count
rolling up to the folders above it.

Worth saying plainly, because it changes what this is: the tree draws no dot
today. Reading the navigator's cell shows it draws an icon, a name and an
optional subtitle, and there is no `ovalIn` anywhere in `Navigator/`. The
rolling-up already exists — `FileNode.applyGitStatus` asks its lookup about
directories too, which is why a folder holding a change has a green name — so
what is missing is only the mark.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-09-01, with a screenshot.

## What Changes

- A row whose node has a version-control state draws a small filled dot at its
  trailing edge, in that state's colour — the same colour the name already
  takes, so the two say one thing rather than two.
- Files and folders alike. A folder's state is already the roll-up of what is
  under it, which is what makes the mark useful on a **collapsed** folder: the
  one case where the file itself cannot be seen.
- `ignored` and `unmodified` draw nothing. Ignored is most of a work tree in
  most projects, and a mark on nearly every row is not a mark.
- The name keeps its colour. Removing it would be a second change of its own
  and would take away the only signal people have today.

## Capabilities

### Modified Capabilities

- `project-view`: gains a requirement for the change mark — which rows carry
  one, what colour it is, and which states draw nothing. No existing
  requirement states how a change is shown; the colouring is not written down.

## Impact

- **AbydosApp**: `NavigatorCellView.draw` gains the dot and takes its width off
  what the name and the subtitle have to fit in, so a long name truncates
  before it reaches the mark rather than drawing under it.
- **Cost**: one fill per drawn row, from a value the cell already reads.
- **Risk**: the navigator is at its size ceiling, so the room has to be found
  before the mark is added.
