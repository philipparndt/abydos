# indentation Specification

## Purpose
TBD - created by archiving change the-editor-follows-the-files-indentation. Update Purpose after archive.
## Requirements
### Requirement: A file's indent style is read from what the file already does

A file SHALL be said to indent with tabs, or with spaces and a width, judged
once from a bounded read of the buffer when it is opened — never per
keypress. The kind SHALL be which begins more of the file's first indented
lines, tabs winning a tie; the width, for a spaces file, SHALL be the most
common run of leading spaces among those lines, a tie going to the narrower.
A file with no indented lines yet, or none that begin with a space, SHALL be
spaces at the app's tab width, which is what return already assumed. The
style SHALL be read again whenever the buffer is replaced wholesale — a
decrypt, a lock, an external reload — because the new text's habit is new.

#### Scenario: a two-space yaml

- **GIVEN** `values.yaml`, every indented line beginning with two spaces
- **WHEN** it is opened
- **THEN** its indent style is spaces of width 2

#### Scenario: a tab-indented Swift file

- **GIVEN** `Main.swift`, its body lines beginning with tabs
- **WHEN** it is opened
- **THEN** its indent style is tabs

#### Scenario: continuation lines cannot outvote the step

- **GIVEN** a file whose lines begin with four spaces, some continuation lines beginning with six
- **WHEN** it is opened
- **THEN** its indent style is spaces of width 4

#### Scenario: a file with no indentation yet

- **GIVEN** an empty file, and the app's tab width set to 4
- **WHEN** it is opened
- **THEN** its indent style is spaces of width 4

### Requirement: The footer says how the file indents, and a menu converts it

The editor footer SHALL show an indent chip on its right side, between the
caret position and the language, reading *Tabs* for a tabs file and
*Spaces: 2* for a file that indents with two — the file's own width, and no
number for tabs, which carry none. Pressing it SHALL open a menu — *Indent
with Tabs*, then *Indent with 2, 4 and 8 Spaces*, with the file's own width
offered beside the standing ones when it is not one of them, and the current
style ticked. Choosing from the menu SHALL convert the buffer's indentation
to the chosen style, level by level — one leading level of the old style, a
tab or the old width in spaces, becoming one level of the new — and SHALL
leave alignment after the first non-blank alone, keep a partial level's
spaces, and be one edit, so one ⌘Z returns the file to what it was. The
chosen style SHALL be the one inserted from here, and every insertion SHALL
follow it at once. The style SHALL be read again whenever the buffer is
replaced wholesale — a decrypt, a lock, an external reload — except by the
conversion itself, whose choice is known without reading; and an undo, a
redo or a history travel SHALL read it again too, because the text has gone
back to a former state and its habit is that state's — the undo of a
conversion takes the chip back with the file.

#### Scenario: the chip names the file's habit

- **GIVEN** `values.yaml` indented with two spaces, opened
- **WHEN** the footer is looked at
- **THEN** a chip between the position and the language reads *Spaces: 2*

#### Scenario: the menu offers the standing widths and the file's own

- **GIVEN** `values.yaml` indented with two spaces, opened
- **WHEN** the chip is pressed
- **THEN** the menu offers *Indent with Tabs*, *Indent with 2 Spaces*, *Indent with 4 Spaces* and *Indent with 8 Spaces*, with *Indent with 2 Spaces* ticked

#### Scenario: choosing converts the file

- **GIVEN** `Main.swift` indented with tabs, its chip reading *Tabs*
- **WHEN** *Indent with 4 Spaces* is chosen from the menu
- **THEN** every leading tab has become four spaces, the chip reads *Spaces: 4*, and ⇥ on a fresh line inserts four spaces

#### Scenario: one undo takes a conversion back

- **GIVEN** `Main.swift` converted to four spaces from tabs
- **WHEN** ⌘Z is pressed once
- **THEN** the file is indented with tabs again and the chip reads *Tabs*

#### Scenario: alignment is not the file's habit

- **GIVEN** a line whose first non-blank character is followed by an alignment tab
- **WHEN** the file's indentation is converted to spaces
- **THEN** the leading indentation is converted and the alignment tab is where it was

#### Scenario: a file with an unusual width is offered it

- **GIVEN** a file indented with three spaces, opened
- **WHEN** the chip is pressed
- **THEN** the menu offers *Indent with 2, 3, 4 and 8 Spaces*, the file's own three beside the standing widths

### Requirement: ⇥, ⇧⇥ and return insert the file's own unit

⇥ with no selection SHALL insert one level of the buffer's style — a tab in
a tabs file, the style's width in spaces in a spaces file. ⇥ with lines
selected SHALL shift every line the selection touches by that same unit, and
⇧Tab SHALL take one level off — a tab, or up to the style's width in spaces —
which is what `LineIndent` does once it is handed the style's numbers instead
of a hardcoded tab. Return's auto-indent SHALL follow the style in kind, as
it already did, and in width, so a two-space file's new lines indent by two
and not by the tab-display setting.

#### Scenario: tab in a two-space file

- **GIVEN** `values.yaml` indented with two spaces, the caret on a fresh line
- **WHEN** ⇥ is pressed
- **THEN** two spaces are inserted, and one undo step takes both back

#### Scenario: tab in a tabs file

- **GIVEN** `Main.swift` indented with tabs, the caret on a fresh line
- **WHEN** ⇥ is pressed
- **THEN** one tab is inserted

#### Scenario: block indent follows the unit

- **GIVEN** three lines selected in `values.yaml`, each beginning with two spaces
- **WHEN** ⇥ is pressed, and ⇧⇥ then
- **THEN** every line begins with four spaces after the first press and with two again after the second, the selection still covering them

#### Scenario: return follows the width

- **GIVEN** `values.yaml` indented with two spaces, the caret after a line that opens a block
- **WHEN** return is pressed
- **THEN** the new line begins with two spaces, not the tab-display setting's width

