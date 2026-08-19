## Why

Drag a file from the Finder onto the editor and nothing happens. The editor's
drop target registers one type:

    container.registerForDraggedTypes([EditorTabDrag.pasteboardType])

so a drag carrying a file URL is not something it recognises, and `EditorDropView`
— which handles the drop — asks only for `EditorTabDrag.payload(from:)` and
returns false for anything else. It is not that the file is refused; the window
never offers to take it, so the drag springs back.

**Everything needed to show that file already exists.** Three of them:

- `application(_:open:)` handles it for a Finder double-click or a drop on the
  Dock icon: a directory opens as a project, a file opens the project enclosing
  it and then the file.
- `openFromTerminal` does it for `abydos <file>` — and does it **without
  changing the window's project**: `editor.open(fileURL:)`, then the tree is told
  to select it. A file from anywhere on the disk opens in the window you are in.
- Three other views in this app already accept `.fileURL`: the terminal, the
  project tree, and the launch configurations page.

So the editor is the one place a person would drop a file *in order to look at
it*, and the one place that will not take it.

The gap is small; the decisions around it are not. What a dropped **directory**
should do, whether a file from outside the project should **change the project**,
and what several files at once mean are questions the existing paths answer
differently from each other — `application(_:open:)` opens the enclosing project,
`openFromTerminal` refuses directories outright and never switches. Those are
settled in `design.md` rather than left to whichever path the drop happens to
reach.

Reported as: it should be possible to drag external files to Abydos and have them
shown in the editor.

## What Changes

- **The editor takes file URLs as well as tabs.** A file dropped anywhere on an
  editor group opens in it, in a tab, the way opening it any other way does.
- **The window's project is not changed by a drop.** `openFromTerminal` is the
  precedent and it is the right one: a file is something to look at, and
  re-pointing somebody's window — its tree, its git, its run configurations, its
  language servers — because they dragged a file in is a large answer to a small
  gesture.
- **A file already inside the project is just opened**, which is what dropping it
  obviously means, and is what the tree's own double-click does.
- **A directory is not a file.** What a dropped folder does is decided in
  `design.md`; the two existing paths disagree, so one answer is chosen and
  written down.
- **Several files open several tabs**, in the order they were dropped, with the
  last in front.
- **The drop zones already there are honoured or explicitly are not.** The group
  highlights a split zone while a *tab* is dragged over it; whether a file
  dropped on the right half opens in a split is decided rather than inherited by
  accident.
- **Not proposed: dropping onto the tab strip as a separate gesture.** The whole
  group is the target, which is what `EditorDropView` already says and why it
  exists.
- **Not proposed: changing what the terminal does with a dropped file.** It
  inserts the path, which is what a shell wants; two targets, two meanings, and
  both are right.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `editor`: that a file dropped on an editor group opens in it, what happens to
  the window's project when it does, and what a folder and a multiple selection
  mean. The capability covers what the editor does with the file in front of it
  and says nothing yet about how a file gets there.

## Impact

- `Sources/AbydosApp/Editor/EditorViewController.swift` — line 516, where the
  container registers `EditorTabDrag.pasteboardType` and nothing else.
- `Sources/AbydosApp/Editor/EditorDropView.swift` — `draggingEntered`,
  `draggingUpdated` and `performDragOperation`, all of which assume the payload
  is a tab. The zone overlay is drawn from the same path.
- `Sources/AbydosApp/MainWindowController.swift` — `openFromTerminal` is the
  behaviour being reused; a dropped file wants the same treatment and probably
  the same function.
- `Sources/AbydosApp/AppDelegate.swift` — `application(_:open:)`, for the
  comparison: it switches project and this must not.
- `.abydos/backlog/spec/editor.md`.
- No new dependency. Nothing on a drawing path: a drop is a gesture, not a frame.
