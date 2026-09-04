## Context

The project tree already has a paste. `NavigatorOutlineView.paste(_:)` answers
⌘V from the Edit menu, `canPaste` answers its validation, and both hand to
`ProjectNavigatorViewController.paste(_:into:)`, which reads
`FilePasteboard.files()`, asks `destinationFolder(for:)` where the paste is
aimed, and hands `FileTransfer` the plan. The row's own menu reaches the same
method through `contextPaste`. Every seam a picture needs is cut; what is
missing is one more reader of the board and a name for a file that has none.

Two precedents disagree about what happens after a file appears. New File
(`commitName`, the `.create` branch) opens it, because somebody who typed a name
is about to type into the file. The diagram export (`revealExported`) selects
and does not open, because an export happens while somebody is working on the
diagram and a PNG tab taking the front would be the export stealing their
place. This design has to pick one.

`FilePasteboard` lives in AbydosKit and imports AppKit for `NSPasteboard`,
which is not view code. `NSBitmapImageRep` is in the same position, so decoding
a board's TIFF into PNG bytes belongs beside it and is testable without a
window.

## Goals / Non-Goals

**Goals:**

- ⌘V, Edit ▸ Paste and *Paste Item* write a board's picture as a PNG file into
  the folder a pasted file would land in.
- The file has a free name, and the row opens for renaming with the stem
  selected.
- The row is revealed and selected; ⌘Z in the tree removes the file.
- The pasteboard reading and the naming are in AbydosKit, tested against a
  scratch board and an injected disk.
- A driven run proves the gesture end to end without touching the general
  clipboard.

**Non-Goals:**

- Dropping a picture (pixels, not a file) from another program onto the tree.
  `registerForDraggedTypes([.fileURL])` refuses it today. It is the same write
  behind a different gesture, and it is left for a change of its own so this
  one stays the size of the request.
- Pasting a picture into an editor or a Markdown document, and writing the
  reference. That is the editor's subject, and the file this change makes is
  what such a feature would refer to.
- Choosing a format. PNG, always; see below.

## Decisions

### The board is read in AbydosKit, as PNG bytes

`FilePasteboard.picture(on:) -> Data?` returns PNG bytes: the board's own
`public.png` item when it has one, otherwise its `public.tiff` decoded through
`NSBitmapImageRep` and re-encoded as PNG. `FilePasteboard.hasPicture(on:)`
asks `availableType(from: [.png, .tiff])` and reads nothing — it is what menu
validation calls, and validation runs every time a menu opens.

*Ruled out:* `NSImage(pasteboard:)`. It is the obvious call and it is a view
class's convenience: it picks a representation by its own rules, drops the
PNG's bytes on the floor and re-encodes from a bitmap, so a PNG that was
already right would be rewritten and could come out larger. Reading the PNG
item when there is one keeps the bytes the program put there.

*Ruled out:* reading in the App. The files reader is in AbydosKit for a reason
its doc comment records — the shape of the board was measured, and a test
against a scratch board is what holds the measurement. The picture reader
wants the same.

### PNG, always

A project wants a lossless file every tool opens and git diffs as a picture
(`picture-diffs`), and a `.png` name says what the file is. A board's TIFF is
what programs put there for other programs, not what anybody keeps.

*Ruled out:* keeping TIFF when that is all the board has. A `.tiff` in a
repository is a question at review time. *Ruled out:* JPEG for photographs.
It would need a rule for telling a photograph from a screenshot, and a wrong
guess loses pixels for good; somebody who wants a JPEG has a program for that.

### Files first

`paste(_:into:)` reads files, and only when there are none asks for a picture.
Copying an image file in the Finder can put pixels beside the file URL;
pasting the file is what somebody who copied a file meant. ⌥⌘V, *Move Item
Here*, stays a files-only gesture: pixels have no origin to move from, and a
move that copies would be a lie in the menu.

### The name is offered, not demanded

The file is written under the first free `picture-<n>.png` in the folder —
`FileTransfer.freeName(stem:extension:in:isTaken:)`, beside `duplicateName`
and sharing its rule: the first number free rather than the next count,
because a gap left by a deletion is a name that is free. Then the row opens
for renaming with the stem selected, through the same `beginEditing(.rename)`
New File's commit uses, so typing replaces the name and Escape keeps it.

*Ruled out:* the New File flow, where nothing is written until Return. It is
right there because Escape has to leave nothing behind, and an empty file is
something. Here the picture is the thing: a paste that Escape could cancel
after the fact would be the only paste in the app that is not done when the
key goes down, and ⌘Z already answers the person who changed their mind.

*Ruled out:* macOS's own `Screenshot 2026-09-03 at 14.02.11.png`. A name with
spaces and a time in it is a name every shell needs quoting for and no
reference in a document reads well with. *Ruled out:* `untitled.png`, New
File's draft. A tree with three pasted pictures would hold `untitled.png`,
`untitled-1.png` and `untitled-2.png`, none of which says what it is.
`picture` is the word the app already uses for the kind (`FilePreview.kind`
says `.image`, the diff says *picture*), and the number is the order they
arrived in.

*Open:* whether the stem should be `screenshot` when the board's producer is
the screenshot service. The board does not say who wrote it, so this is not
decidable today and the design does not pretend to decide it.

### Revealed and selected, not opened

The row is put in `pendingReveal` and selected when the watcher's reload
finds it, as every created file is. It is not opened. A picture is pasted into
a project to be referred to from something being written, and the rename field
needs the keyboard the editor would take; the diagram export's reasoning
applies word for word. Return on the row opens it, as any row's does.

*Ruled out:* opening it, as New File does. New File opens because a name was
typed and the file is about to be typed into; a picture is not typed into.

### Undo is the tree's, through `FileUndo.created`

The same record New File makes, with its guard: a file modified since it was
created is not thrown away by ⌘Z. A pasted picture is unlikely to be written
to, but the guard costs nothing and the record is the existing one.

### The driven proof uses a board of its own

`paste(_:into:from:)` takes the board as a parameter, defaulting to
`.general`. The driver's `paste-picture:<path>` step reads the PNG at the path
onto a named board and pastes from it, so a driven run never writes the
clipboard of whoever is at the keyboard — which `screenshots` forbids in so
many words. `copy-files`/`paste` go through the general board today, and
that precedent is not extended.

## Risks / Trade-offs

- [The board holds a picture the decoder refuses — a truncated TIFF, an
  exotic representation] → `picture(on:)` returns nil, the paste does nothing,
  and a toast says *The clipboard's picture could not be read*, so silence is
  never the answer to a ⌘V that was heard.
- [A large picture, a 5k screenshot, encoded on the main thread] → one PNG
  encode of a screenshot is tens of milliseconds and happens once per paste,
  on a gesture that expects a beat. Not worth a thread; measured in the driven
  run and said in the notes.
- [Menu validation asked often] → `hasPicture` reads types, not bytes. The
  files check beside it already reads objects and has not shown up.
- [A paste aimed at a folder that has since gone] → `destinationFolder` gives
  the parent; the write fails with the file system's reason and the toast
  says so, as a file transfer's failure does.
- [The rename field is up when ⌘V arrives] → `handleKeyDown` already declines
  while `nameField` is non-nil, and the field's own paste takes the text.
  Pixels pasted into a name field do nothing, which is right.
