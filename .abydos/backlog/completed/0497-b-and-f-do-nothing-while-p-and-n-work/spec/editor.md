<!-- What this item changes about `editor`. Folded into
     .abydos/backlog/spec/editor.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       ⌘/ comments out the lines a selection touches
       the comment goes at the indent the lines share
       blank lines are neither commented nor counted
       the selection still covers the same text afterwards
       a language with no line comment says so rather than nothing
       an embedded language gets its host's comment, not its own
       ⌘/ is ⌘/ on every keyboard
       ↑ on the first line and ↓ on the last go to the edge of the file
       Shift takes the selection to the edge with it

     One ADDED, and not a MODIFIED of either of 0494's and 0495's two.
     Both of those are about the *edges of the file* — a key that ran out
     of rows, or the jump whose whole purpose is the end of the document —
     and neither says anything about ← and → or about a single character.
     "Shift takes the selection to the edge with it" is the closest, and
     folding ⇧⌃F into it would put a one-character motion under a sentence
     whose subject is the edge of the document: two rules in one heading,
     which is the drift a MODIFIED is supposed to prevent rather than
     cause. The one sentence they share — Shift decides only whether the
     selection comes along — is stated here about this motion rather than
     borrowed, and that is a repetition worth having because it is the
     rule the four keys of this requirement obey.

     Nothing about ← and → was in the spec at all before this. The new
     requirement says what the editor does about *both* orders, because
     the interesting part is that it has only one.
-->

## ADDED Requirement: ⌃B and ⌃F move the caret a character, and so do ← and →

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

The rest of the emacs family is not this requirement. ⌃P and ⌃N move up and
down a line because macOS sends them as the same selectors the arrows send.

### Scenario: ⌃F and ⌃B in the middle of a line

- **Given** the caret at offset 50, which is column 6 of `third line of the file`
- **When** ⌃F is pressed
- **Then** the caret is at offset 51 and nothing is selected
- **And** ⌃B from offset 50 puts it at 49, also with nothing selected

### Scenario: ⇧⌃F and ⇧⌃B take the character with them

- **Given** the caret at offset 50, with the `l` of `line` in front of it
- **When** ⇧⌃F is pressed
- **Then** the caret is at offset 51 and `l` is selected
- **And** ⇧⌃B from offset 50 puts the caret at 49 with the space before `line` selected

### Scenario: ⌃F over an emoji

- **Given** the caret at offset 50, with `🙂` in front of it
- **When** ⇧⌃F is pressed
- **Then** the caret is at offset 52 and the whole `🙂` is selected, not half of it

### Scenario: ⌃B at the start of a line

- **Given** the caret at column 0 of the third line, which is offset 44
- **When** ⌃B is pressed
- **Then** the caret is at offset 43, the end of the line above

### Scenario: ⌃B at the start of the file

- **Given** the caret at offset 0
- **When** ⌃B is pressed
- **Then** the caret is still at offset 0 and nothing is selected
