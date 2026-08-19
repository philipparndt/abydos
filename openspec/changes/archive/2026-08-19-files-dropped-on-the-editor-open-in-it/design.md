## Context

The editor group's root view is `EditorDropView`, and it exists to be a drop
target: the whole group, not just the tab strip, so a tab can be dropped over the
text. It highlights one of five zones while a drag is over it, and on drop asks

    EditorTabDrag.payload(from: sender.draggingPasteboard)

returning false for anything that is not a tab. The container registers exactly
one type — `EditorTabDrag.pasteboardType` — so a drag carrying a file URL is
never offered to the window at all.

Three paths in this app already open a file, and they do not agree about what
else that entails:

| path | directory | project |
| --- | --- | --- |
| `application(_:open:)` | opens it as a project | opens the one enclosing the file |
| `openFromTerminal` | refuses it outright | **unchanged** |
| the tree's double-click | expands it | unchanged |

`openFromTerminal`'s comment says why it refuses: "A directory is a project,
whoever asked; that is what `abydos` with no arguments means and it is not this
window's to reinterpret."

Three views already accept `.fileURL`: `TerminalView` (twice — a shell wants the
path typed into it), the project tree (`0436`: rows dropped back in, and files
from the Finder), and the launch configurations page.

## Goals / Non-Goals

**Goals:**

- A file dragged from anywhere onto an editor group opens in it.
- Nothing else about the window changes because of it.
- Several files at once behave the way opening several files behaves.
- A folder does what a folder does everywhere else in this app.

**Non-Goals:**

- Changing what the terminal does with a dropped file. It inserts the path, which
  is what a shell wants. Two targets, two meanings.
- Changing what the tree does. It copies or moves the file into the project,
  which is a different verb from "show me this".
- Copying the dropped file anywhere. A file opened from outside the project is
  read where it lies, which is what `abydos /etc/hosts` already does.
- Accepting text, images or anything else off the pasteboard. This is about
  files; a dropped *snippet* is a separate question with its own answer.

## Decisions

**A dropped file opens in this window and does not change its project.**
`openFromTerminal` is the precedent, and the reason it is the right one is what
switching costs: the tree, git, the run configurations, the language servers and
the remembered session all belong to the project, so re-pointing them because
somebody dragged a file in is a very large answer to a very small gesture. The
file opens in a tab; the window stays where it was.

This differs from `application(_:open:)`, deliberately, and the difference is not
inconsistency: a file dropped on the **Dock icon** is addressed to the
application, which has no window in mind and must find one. A file dropped on a
**window** is addressed to that window.

**A dropped folder opens as a project.** Not refused, and not opened as a wall of
tabs. A folder means a project everywhere else here — `abydos <dir>`, the Dock
icon, the switcher — and it goes through `open(projectAt:from:)` with this window
as the source, so it obeys `Settings.shared.opensProjectsInNewWindow` and it
raises an existing window if that project is already open. That is one rule for
folders across the whole app, and this adds no sixth variant.

A drag holding both files and folders is not a case to invent behaviour for: the
folders open as projects and the files open as files, each doing what it would
have done alone.

**`.copy`, not `.move`, and this is the trap.** The tree already carries the
lesson — "`validateDrop` returning an operation the source never permitted is a
drop that quietly does nothing." `EditorDropView` currently answers `.move` to
everything, which is right for a tab being dragged between groups and is exactly
what the Finder does not offer for an external file. Answering `.move` to a
Finder drag is a drop that springs back, indistinguishable from the fault being
fixed. What is offered is decided from what the drag permits.

**The zone highlight is for tabs only, and a dropped file lands in the group.**
The five-zone overlay answers "where does this pane go", which is a question
about splitting the group. A file is not a pane; it is a tab. Opening a file into
a new split on the strength of which half of the view the pointer was over is a
gesture nobody asked for and one that cannot be undone by dropping it again.
While a file is over the group the highlight is the whole group, so what is shown
is what will happen.

*Left open below*: whether dropping a file on the right half **should** split, as
a deliberate feature rather than an accident of the existing overlay.

**Several files open several tabs, in the order given, last one in front.** Which
is what `application(_:open:)` does with several URLs and what opening several
files from the tree does. Not preview tabs: a preview tab is the answer to a
single click in the tree, where the next click replaces it, and a drag is a
deliberate act.

**The opening itself is `MainWindowController`'s, not the group's.** The group
knows about tabs; opening a file needs the tree told to select it and the panel
made room for, both of which `openFromTerminal` already does. Reusing that path
rather than writing a second one is the same argument as everywhere else here:
two functions that agree today are two that can disagree later.

## What the driven runs showed

A real drag cannot be scripted, so `--drop-files` puts the URLs on a pasteboard
and hands it to the group's drop view through the same `draggingEntered` and
`performDragOperation` AppKit would — the path a drag takes, not the opening
underneath it.

**A file from outside the project, with the project printed either side:**

    DROP before: project=droptarget tabs=[*own.txt]
    DROP offered: copy
    DROP accepted: true
    DROP after:  project=droptarget tabs=[own.txt, *one.md]

Three things at once: the operation offered is `copy`, which is what the drag
permits — answering `.move` there is the trap the tree already warns about, and
it would have looked exactly like the drag not being accepted. The file opened.
And the project did not move, which is the half a report of tabs alone would not
have shown.

**What the before-state is, and how it is known.** Read from the code, not
driven: `container.registerForDraggedTypes([EditorTabDrag.pasteboardType])` names
one type, so AppKit never offered a file drag to the window at all, and
`performDragOperation` asked only for `EditorTabDrag.payload(from:)` and returned
false for anything else. Measuring it would have meant reverting the two files
the driver verb now lives in — the same bind as the find change — so it is
labelled a reading rather than dressed up as an observation.

**Three at once:**

    DROP after: project=droptarget tabs=[own.txt, one.md, two.md, *three.md]

In the order dropped, last one in front, none of them provisional.

**A folder, and the mixed case — which this got wrong and the run caught.**

A folder alone behaves as decided:

    DROP after: project=inner-project tabs=[]

A folder *with* a file did not. Files were opened first, on the reasoning written
into the code at the time — "after the files, so a drag holding both leaves the
project open rather than a file in the project that was left" — and the
measurement said:

    DROP after: project=inner-project tabs=[]

The file was gone. Opening it into the project being *left* and then switching
restores the arriving project's session over the top, so the file was discarded
by the very step that was supposed to follow it. "Each does what it would have
done alone" was false, and the comment claiming otherwise was exactly backwards.

Folders now open first and the files go to the window that results:

    DROP after: project=inner-project tabs=[*two.md]

Which is the better answer anyway: drag a folder and a file together and you get
that project, showing that file. With several folders the first one takes the
files, being the one the drop was aimed at.

**The tab drag, which shares the function this change edited:**

    TABDRAG before: groups=1 tabs=[own.txt, *one.md]
    TABDRAG offered: move
    TABDRAG after:  groups=2

**It read as a regression first, and was the measuring instrument.** The first
two runs reported `groups=1` — no split — from a harness that handed
`draggingLocation` a point in *view* coordinates. `updateZone` converts from nil,
which is the window, so the point landed in the centre zone; and a centre drop
onto a tab's own group is refused deliberately:

    if source === target, zone == .center { return }

The product was right and the check was wrong, which is the reverse of the usual
and worth writing down: a driven check is a thing that can be broken too, and
`groups=1` was a true report of a drag that never went where it was aimed.

## Risks / Trade-offs

- **`draggingEntered` currently returns `.move` unconditionally**, and the drop
  path assumes a tab. Getting this wrong makes the feature look present and do
  nothing. → The operation is derived from the drag rather than stated, and the
  driven check drops a real file rather than trusting the code.
- **A file dropped from outside the project has no project.** Its language server
  root, its git status, its place in the tree — all absent or elsewhere. → That
  is already true of `abydos /etc/hosts` and is not made worse here. The file
  opens and the parts of the window that are about the project stay about the
  project.
- **A drag can carry a URL that is not a file** — a web URL from a browser. →
  Only file URLs are accepted, and anything else is declined so the drag springs
  back rather than opening an empty tab named after a website.
- **A very large file, or thousands of them dropped at once.** → The existing
  open path already refuses to open an oversized file as text and offers a hex
  view instead; nothing new is needed for the first. The second is a real limit
  and is named as an open question rather than guessed at.

## What was ruled out

**Opening a dropped file into a split**, on the strength of which half of the
view the pointer was over. The five-zone overlay is right there and the gesture
would read well to anybody who has dragged a tab — but a file is a tab, not a
pane, and a split made from where a pointer happened to be is not undone by
dropping the file again. Left as an open question rather than done by accident,
which is what inheriting the overlay would have been.

**Switching the window's project to the one containing a dropped file**, which is
what `application(_:open:)` does. That path is addressed to the *application*,
which has no window in mind and must find one. A drop is addressed to a window.

**Copying the file into the project.** A file opened from outside is read where
it lies, which is what `abydos /etc/hosts` already does. The tree's own drop does
copy or move, and that is a different verb from "show me this" — two targets, two
meanings, both right.

**Accepting anything but files.** A browser puts an `https:` URL on the board and
`NSURL` reads it happily; a tab named after a website is worse than a drag that
springs back.

**Refusing a drag that holds both files and folders.** Easy to write and
unhelpful: each half has an obvious meaning, and the only real question was the
order — which the measurement settled.

## Open Questions

- Should a file dropped on the right or bottom half open in a **split**, as a
  feature? The overlay is already there and the gesture would read well to
  anybody who has dragged a tab. Left out of this change because it is a second
  behaviour and the report asked for the first; worth doing next if dropping
  files turns out to be something people do often.
- How many files at once is too many? Dropping a folder's worth of files by
  selecting them all is easy to do by accident. Nothing here bounds it, and a
  bound wants a number somebody has hit rather than one invented now.
- Should the tree select the last dropped file, as `openFromTerminal` does? It
  will, by reusing that path — but for a file *outside* the project there is no
  row to select, and what that does is worth watching in the driven run.
