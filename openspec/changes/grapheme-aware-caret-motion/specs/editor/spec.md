## MODIFIED Requirements

### Requirement: ⌃B and ⌃F move the caret a character, and so do ← and →

⌃B and ⌃F SHALL move the caret a character, and so SHALL ← and →. A character SHALL
be a grapheme cluster, so the caret SHALL NOT come to rest inside one.

The editor has one horizontal character motion and it is **logical**: a step
forward is one character further into the document, a step back is one
character towards its start. Four key bindings arrive at it. ← and → send
`moveLeft:` and `moveRight:`, which name a visual direction; ⌃B and ⌃F send
`moveBackward:` and `moveForward:`, which name a logical one. In a file of
left-to-right text those are the same motion, and this editor treats them as
the same motion everywhere.

That is a decision and not an accident, and its limit is written down: in
right-to-left text logical forward is leftward on the screen, so ⌃F would be
correct and → would not. The editor does not lay text out bidirectionally —
every offset it works in is logical, and reordering happens only when a line
is drawn — so there is no second, visual motion for the arrows to answer to.
An editor that gained right-to-left support would have to give them one; until
then ⌃F and → agree, and ⌃B and ← agree.

Shift decides only whether the text stepped over comes with the caret. ⇧⌃F
extends the selection forward by the character it moves over and ⇧⌃B backward
by one, exactly as ⇧→ and ⇧← do.

A character is a composed character, so an emoji or a letter with a combining
mark is one step and not two. At the start of a line the character before the
caret is the newline that ended the line above, so ⌃B goes to the end of that
line; at offset zero there is nothing to step over and the caret stays.

**That sentence was half true for as long as it stood here, and 0504 is what it
cost.** The alignment the four keys went through was `Rope.alignToBoundary`, which
walks back over UTF-8 continuation bytes — code-point alignment, not grapheme
alignment. An emoji is a single code point, so the emoji scenario below passed and
the claim looked kept. `e` + U+0301 is two code points and neither begins with a
continuation byte, so the caret stopped between the letter and its accent: where no
caret should ever be, and where the next keystroke edits half a character. The step
is now a grapheme step, and the sentence is true rather than aspirational.

`\r\n` is one grapheme and two code points. The caret does not stop between them,
which is the same fact that makes ⌃O's two halves cancel after a lone `\r`.

The rest of the emacs family is not this requirement. ⌃P and ⌃N move up and
down a line because macOS sends them as the same selectors the arrows send.

#### Scenario: ⌃F and ⌃B in the middle of a line

- **Given** the caret at offset 50, which is column 6 of `third line of the file`
- **When** ⌃F is pressed
- **Then** the caret is at offset 51 and nothing is selected
- **And** ⌃B from offset 50 puts it at 49, also with nothing selected

#### Scenario: ⇧⌃F and ⇧⌃B take the character with them

- **Given** the caret at offset 50, with the `l` of `line` in front of it
- **When** ⇧⌃F is pressed
- **Then** the caret is at offset 51 and `l` is selected
- **And** ⇧⌃B from offset 50 puts the caret at 49 with the space before `line` selected

#### Scenario: ⌃F over an emoji

- **Given** the caret at offset 50, with `🙂` in front of it
- **When** ⇧⌃F is pressed
- **Then** the caret is at offset 52 and the whole `🙂` is selected, not half of it

#### Scenario: ⌃F over a decomposed accent

- **Given** a line whose second character is `e` followed by U+0301, beginning at
  offset 13
- **When** ⌃F is pressed with the caret at offset 13
- **Then** the caret is at offset 15, not 14
- **And** ⌃B from offset 15 puts it back at 13

#### Scenario: ⇧→ over a ZWJ sequence

- **Given** the caret immediately before a ZWJ sequence — a family emoji, or a
  skin-tone modifier
- **When** ⇧→ is pressed
- **Then** the whole sequence is selected, not the first code point of it

#### Scenario: ⌃B at the start of a line

- **Given** the caret at column 0 of the third line, which is offset 44
- **When** ⌃B is pressed
- **Then** the caret is at offset 43, the end of the line above

#### Scenario: ⌃B at the start of the file

- **Given** the caret at offset 0
- **When** ⌃B is pressed
- **Then** the caret is still at offset 0 and nothing is selected

#### Scenario: a line ending of two code points

- **Given** a document using `\r\n` line endings
- **When** the caret steps over a line ending
- **Then** it does not stop between the `\r` and the `\n`

## ADDED Requirements

### Requirement: Deleting crosses the same boundary as moving

⌫ and ⌦ SHALL remove a whole grapheme cluster, so that no keystroke leaves a
combining mark without its base letter or a base letter without its mark. What counts
as one character SHALL be the same for deleting as for moving.

Two answers to "where is the next character boundary" is how the two come to
disagree later, which is the fault this pair of requirements exists to close. One
test holds the motion and the deletion to the same boundary.

#### Scenario: ⌫ after a decomposed accent

- **Given** the caret immediately after `e` + U+0301
- **When** ⌫ is pressed
- **Then** both the letter and its combining mark are removed, and no orphaned mark
  is left in the document

#### Scenario: ⌦ before a decomposed accent

- **Given** the caret immediately before `e` + U+0301
- **When** ⌦ is pressed
- **Then** both code points are removed together

#### Scenario: the two agree

- **Given** any character the horizontal keys step over in one press
- **When** ⌫ is pressed with the caret after it
- **Then** exactly that character is removed
