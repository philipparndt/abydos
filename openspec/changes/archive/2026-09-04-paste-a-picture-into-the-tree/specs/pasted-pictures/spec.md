# Pasted Pictures

## Purpose

What a picture on the clipboard becomes when it is pasted into the project
tree: a PNG file where a pasted file would land, under a name that is offered
rather than demanded, revealed and not opened, and undone by the tree's ⌘Z.

## ADDED Requirements

### Requirement: A picture on the clipboard pastes into the tree as a file

The project tree SHALL accept a pasteboard that carries an image and no file
URL through ⌘V, Edit ▸ Paste and the row menu's *Paste Item*, and SHALL write
the image as a PNG file into the folder a pasted file would land in: the
selected folder, the folder holding the selected file, or the project root
when nothing is selected. The row menu's paste SHALL aim at the clicked row's
folder, as it does for files.

A pasteboard that carries PNG bytes SHALL be written byte for byte. One that
carries only TIFF SHALL be decoded and written as PNG. A picture the app
cannot decode SHALL leave nothing behind and SHALL be said in a toast.

#### Scenario: a screenshot pasted onto a folder

- **GIVEN** a screenshot on the clipboard and the folder `docs/images` selected
- **WHEN** ⌘V is pressed
- **THEN** `docs/images/picture-1.png` exists and decodes to the screenshot's pixel size

#### Scenario: a picture pasted onto a file

- **GIVEN** a picture on the clipboard and `docs/README.md` selected
- **WHEN** ⌘V is pressed
- **THEN** the file is written into `docs`, beside the README

#### Scenario: the board holds only TIFF

- **GIVEN** a pasteboard carrying `public.tiff` and no `public.png`
- **WHEN** it is pasted into the tree
- **THEN** the file written is a PNG of the same pixel size

#### Scenario: a picture that cannot be read

- **GIVEN** a pasteboard whose image bytes the decoder refuses
- **WHEN** ⌘V is pressed
- **THEN** no file is written and a toast says the clipboard's picture could not be read

### Requirement: Files come first, and a picture is only ever copied

A pasteboard that carries file URLs SHALL be pasted as those files whether or
not it also carries an image. *Move Item Here* (⌥⌘V) SHALL act on files only
and SHALL be disabled for a pasteboard that carries an image and no file.

#### Scenario: a file copied in the Finder that also carries pixels

- **GIVEN** a pasteboard with a file URL to `logo.png` and a `public.png` item beside it
- **WHEN** ⌘V is pressed in the tree
- **THEN** `logo.png` is copied in under its own name and no `picture-1.png` is made

#### Scenario: move is not offered for pixels

- **GIVEN** a pasteboard with an image and no file
- **WHEN** the row menu opens
- **THEN** *Paste Item* is enabled and *Move Item Here* is not

### Requirement: Paste is enabled by the board's types alone

Whether Paste is enabled — in the Edit menu, in the row menu — SHALL be
decided from the pasteboard's declared types and SHALL NOT read or decode the
image. A pasteboard with neither a file URL nor an image SHALL leave Paste
disabled.

#### Scenario: a menu opens over a board with a picture

- **GIVEN** an image on the clipboard
- **WHEN** the Edit menu opens with the tree holding the keyboard
- **THEN** Paste is enabled and no image bytes have been read

#### Scenario: a menu opens over plain text

- **GIVEN** only text on the clipboard
- **WHEN** the row menu opens
- **THEN** *Paste Item* is disabled

### Requirement: The name is offered, not demanded

A pasted picture SHALL be written under the first free `picture-<n>.png` in
its folder, numbered from one and taking the first free number rather than the
next count. The tree SHALL then open the new row for renaming with the stem
selected, so that typing replaces the name and Escape keeps it. The file SHALL
exist from the moment of the paste; Escape SHALL NOT remove it.

#### Scenario: the first picture in a folder

- **GIVEN** a folder with no `picture-*.png` in it
- **WHEN** a picture is pasted there
- **THEN** it is `picture-1.png`, and the row is in a name field with `picture-1` selected

#### Scenario: a gap is a free name

- **GIVEN** a folder holding `picture-1.png` and `picture-3.png`
- **WHEN** a picture is pasted there
- **THEN** it is `picture-2.png`

#### Scenario: a name typed over the offer

- **GIVEN** the name field open on a pasted `picture-1.png`
- **WHEN** `editor-zoomed` is typed and Return pressed
- **THEN** the file is `editor-zoomed.png` and the row is selected

#### Scenario: Escape keeps the offered name

- **GIVEN** the name field open on a pasted `picture-1.png`
- **WHEN** Escape is pressed
- **THEN** `picture-1.png` still exists and its row is selected

### Requirement: The row is revealed and selected, not opened

After a paste, the new file's row SHALL be revealed — its folder expanded — and
selected, and the file SHALL NOT be opened in the editor. Return on the row
SHALL open it as a picture, as Return on any picture row does.

#### Scenario: the editor keeps its place

- **GIVEN** `notes.md` open and being edited, and a picture on the clipboard
- **WHEN** ⌘V is pressed in the tree
- **THEN** the picture's row is selected in the tree and `notes.md` is still the front tab

#### Scenario: Return opens it

- **GIVEN** a pasted picture's row selected after its name was committed
- **WHEN** Return is pressed
- **THEN** the picture opens in an image tab

### Requirement: Undo removes the pasted picture

⌘Z in the tree after a paste SHALL remove the pasted file, on the tree's own
undo stack, with the guard every created file has: a file written to since it
was pasted SHALL NOT be removed.

#### Scenario: undo straight after a paste

- **GIVEN** a picture just pasted as `picture-1.png`
- **WHEN** ⌘Z is pressed with the tree holding the keyboard
- **THEN** `picture-1.png` is gone from the folder and from the tree, and the Edit menu's undo said *Undo Paste*

#### Scenario: undo after the file was changed

- **GIVEN** a pasted `picture-1.png` that another program has since written to
- **WHEN** ⌘Z is pressed in the tree
- **THEN** the file is left where it is

### Requirement: A driven run pastes from a board of its own

A driven run SHALL be able to paste a picture into the tree from a named
pasteboard the run creates, so that proving the gesture never writes the
general clipboard. The step SHALL report the path written and the pixel size
of the file, so the report can be checked against the picture given.

#### Scenario: the driver pastes a PNG

- **GIVEN** a scratch project open in a driven run and a folder row selected
- **WHEN** the step `paste-picture:<path to a PNG>` runs
- **THEN** the report names the file written and its pixel size, and the general clipboard is as it was
