## Why

A screenshot on the clipboard has nowhere to go in this app. ⌘V in the project
tree pastes *files* — `FilePasteboard.files()` reads file URLs and
`FileTransfer` plans where they land — and a board that holds pixels and no
file is, to the tree, an empty board: Paste stays grey in the Edit menu and in
the row's own menu, and nothing happens. The way round today is to save the
picture somewhere with another program and drag the file in, which is four
steps for something that is one everywhere else pictures are pasted.

Asked for on 2026-09-03: "it shall be possible to paste a graphic (e.g.
screenshot) in the project tree. It is pasted as a file."

There is no originating `.abydos/backlog` item. The tree's file operations —
⌘C, ⌘V, ⌥⌘V, drop, New File, rename, its undo stack — were built under items
0411, 0426, 0436, 0439, 0442, 0453, 0482, 0499, 0532 and 0537, and none of them
has an OpenSpec requirement yet; this is the first.

## What Changes

- **A picture on the clipboard pastes into the tree as a file.** ⌘V, Edit ▸
  Paste and the row menu's *Paste Item* accept a board that carries an image
  and no file, and write it as a PNG into the folder the paste is aimed at —
  the selected folder, the folder holding the selected file, or the project
  root — exactly where a pasted file would land.
- **It is a PNG, always.** A board that carries PNG bytes is written as they
  are; one that carries only TIFF (what many programs put beside the PNG, and
  what some put alone) is decoded and encoded as PNG. What a project wants is a
  lossless file every tool opens, and a name that says what it is.
- **The name is offered, not demanded.** The file is written under a free
  name, `picture-1.png` and counting, and the row opens for renaming with the
  stem selected, as New File does. Typing replaces the name; Escape keeps it.
  The paste is done the moment ⌘V is pressed, so Escape leaves a file behind on
  purpose — the picture was the point, and the name is a courtesy.
- **The row is revealed and selected, not opened.** A screenshot is pasted
  into a project to be referred to from something being written; an image tab
  taking the front of the editor would be the paste stealing that place. The
  same rule the diagram export follows.
- **Undo removes it.** ⌘Z in the tree is the paste's undo, on the tree's own
  stack, with the guard every created file has: one that was written to since
  is not thrown away.
- **Files still come first.** A board that holds file URLs is pasted as those
  files whether or not it also holds pixels; only a board with an image and no
  file is a picture paste. *Move Item Here* (⌥⌘V) stays for files: pixels have
  nowhere to be moved from.
- **The check is cheap.** Whether Paste is enabled is asked on every menu
  validation; it looks at the board's types and decodes nothing.

## Capabilities

### New Capabilities

- `pasted-pictures`: what a picture on the clipboard becomes when it is pasted
  into the project tree — where it goes, what it is called, what format it is,
  which gestures reach it, what is revealed, and what undo does.

### Modified Capabilities

None. `previews` says how a picture opens once it is a file, and is unchanged;
`tree-behaviour` is about selection and drawing, and the pasted row is
selected the way every created row is.

## Impact

- **AbydosKit**: `FilePasteboard` gains a reader for a picture beside the one
  for files — the board's PNG bytes, or its TIFF decoded and encoded as PNG —
  and a `hasPicture` that asks the board's types without reading them. A free
  name for a file that has none, beside `FileTransfer.duplicateName`, which
  names a file that has one. Both tested against a scratch board, never the
  general one.
- **AbydosApp**: `ProjectNavigatorViewController.paste(_:into:)` takes the
  picture path when there are no files; `NavigatorOutlineView.canPaste` and
  `menuNeedsUpdate` enable Paste for it; the created file goes through
  `FileUndo.created`, `pendingReveal` and `beginEditing(.rename)`. Nothing new
  in `Controls/`: the shared tree layer is about selection, not files.
- **Driver**: a `paste-picture:<path>` step that puts a PNG on a board of the
  run's own and pastes from it, so a driven run proves the gesture without
  writing the clipboard of whoever is at the keyboard.
- **Cost**: one board read and at most one PNG encode per paste; menu
  validation asks `availableType` and touches no bytes.
