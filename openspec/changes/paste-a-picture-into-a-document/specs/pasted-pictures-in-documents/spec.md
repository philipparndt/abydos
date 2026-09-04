# Pasted Pictures in Documents

## Purpose

What a picture on the clipboard becomes when it is pasted into a document
being edited: a PNG file in `images/` beside the document, named for the
document, and a reference to it at the caret in the document's own syntax.

## ADDED Requirements

### Requirement: A picture pasted into a document becomes a file and a reference

⌘V in the editor over a pasteboard that carries an image and no text SHALL,
for a document whose language has a picture syntax, write the image as a PNG
into a folder named `images` beside the document — created when it is not
there — and SHALL insert a reference to that file at the caret, replacing the
selection if there is one. A pasteboard that carries text SHALL paste the
text, as it always has.

#### Scenario: a screenshot pasted into a Markdown document

- **GIVEN** `docs/notes.md` open with the caret on an empty line, and a screenshot on the clipboard
- **WHEN** ⌘V is pressed
- **THEN** `docs/images/notes-1.png` exists and the line reads `![](images/notes-1.png)`

#### Scenario: the folder is made on first use

- **GIVEN** a document in a folder with no `images` in it
- **WHEN** a picture is pasted
- **THEN** `images` exists beside the document afterwards, holding the picture

#### Scenario: text on the board is still text

- **GIVEN** a pasteboard carrying a paragraph of text and an image
- **WHEN** ⌘V is pressed in a Markdown document
- **THEN** the text is inserted and no file is written

### Requirement: The file is named for the document

The picture SHALL be named after the document's stem with the first free
number, `notes-1.png` for `notes.md`, taking the first number free rather
than the next count.

#### Scenario: a second picture in the same document

- **GIVEN** `images/notes-1.png` exists beside `notes.md`
- **WHEN** a picture is pasted into `notes.md`
- **THEN** it is `images/notes-2.png`

#### Scenario: two documents share the folder

- **GIVEN** `readme.md` and `notes.md` in one folder
- **WHEN** a picture is pasted into each
- **THEN** `images/readme-1.png` and `images/notes-1.png` exist, and neither document references the other's

### Requirement: The reference is in the document's syntax, and the caret is where the description goes

The reference SHALL be `![](<relative path>)` in Markdown and
`<img src="<relative path>" alt="">` in HTML, with the path relative to the
document. After the paste the caret SHALL be inside the empty description —
between `[` and `]`, or inside `alt=""` — with nothing selected, so that the
next thing typed is the description.

#### Scenario: the caret lands in the brackets

- **GIVEN** a picture pasted into a Markdown document
- **WHEN** `the editor zoomed` is typed
- **THEN** the line reads `![the editor zoomed](images/notes-1.png)`

#### Scenario: HTML gets an img tag

- **GIVEN** `docs/index.html` open and a picture on the clipboard
- **WHEN** ⌘V is pressed
- **THEN** `<img src="images/index-1.png" alt="">` is inserted with the caret inside the quotes of `alt`

### Requirement: A language with no picture syntax pastes nothing

⌘V over a pasteboard that carries an image and no text SHALL do nothing in a
document whose language has no picture syntax, and Paste SHALL be disabled in
the Edit menu there. No file SHALL be written.

#### Scenario: pixels into a Swift file

- **GIVEN** `main.swift` open and only a screenshot on the clipboard
- **WHEN** the Edit menu opens
- **THEN** Paste is disabled, and ⌘V writes no file

### Requirement: The preview shows the picture as soon as it is referenced

A Markdown document shown beside its preview SHALL render the pasted picture
in the preview once the reference is inserted, resolved against the
document's folder.

#### Scenario: the preview catches up

- **GIVEN** `notes.md` open with its preview beside it
- **WHEN** a picture is pasted
- **THEN** the preview shows the picture where the reference is

### Requirement: The editor's undo takes the reference back and leaves the file

⌘Z in the editor after a paste SHALL remove the reference as one undo and
SHALL NOT remove the file. The file SHALL be visible in the project tree, where
the tree's own gestures apply to it.

#### Scenario: undo in the editor

- **GIVEN** a picture just pasted into `notes.md`
- **WHEN** ⌘Z is pressed with the editor holding the keyboard
- **THEN** the reference is gone from the line and `images/notes-1.png` still exists

### Requirement: A paste that cannot write inserts nothing

The editor SHALL insert nothing when the picture cannot be read from the
board or the file cannot be written, and SHALL say why in a toast.

#### Scenario: a read-only folder

- **GIVEN** a document in a folder the app cannot write into
- **WHEN** a picture is pasted
- **THEN** the document is unchanged and a toast names the file system's reason

### Requirement: A driven run pastes a picture from a board of its own

A driven run SHALL be able to paste a picture into the open document from a
named pasteboard the run creates, and the step SHALL report the file written
and the text of the line it was written into, without writing the general
clipboard.

#### Scenario: the driver pastes into a Markdown document

- **GIVEN** a scratch project open in a driven run with `notes.md` in the editor
- **WHEN** the step `paste-picture:<path to a PNG>` runs
- **THEN** the report names `images/notes-1.png` and shows the line holding the reference, and the general clipboard is as it was
