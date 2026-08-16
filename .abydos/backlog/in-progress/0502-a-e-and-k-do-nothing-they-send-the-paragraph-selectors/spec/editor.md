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
       ⌃B and ⌃F move the caret a character, and so do ← and →

     Two ADDED and no MODIFIED, and the second of the two is the one worth
     arguing about.

     Not a MODIFIED of 0497's "⌃B and ⌃F move the caret a character". That
     one is about a *character*, and its subject is which of two orders the
     editor has — a question this family does not raise, since a line has
     the same two ends in either order. The sentence the two share, that
     Shift decides only whether the text comes along, is stated again here
     rather than borrowed: it is the rule these eight keys obey and it is
     what makes ⇧⌃A readable without going and finding another heading.
     0497 made the same call about 0494's and 0495's requirements and gave
     the same reason.

     Not a MODIFIED of 0494's or 0495's either. Both of those are about the
     *edges of the file*, and nothing in this family reaches one.

     The two ADDED are separate because one moves and one deletes, and the
     second is where the newline gets decided. Putting ⌃K under the motions
     would hide a rule about what a deleting key takes inside a heading
     about where a caret lands.
-->

## ADDED Requirement: ⌃A and ⌃E go to the ends of the line, and so do ⌥↑ and ⌥↓

A paragraph in this editor is one **line** of the file: the text between two
hard line breaks. That is what macOS means by the word — every key below is
bound to a selector with `Paragraph` in its name — and in a file of source it
is a line. Nothing here looks for a blank line, and nothing here asks about a
soft-wrap row, because a paragraph is bounded by hard breaks whether the row it
is drawn on is or not.

Eight keys arrive at that definition. ⌃A goes to the start of the line the
caret is on and ⌃E to its end. ⌥↑ and ⌥↓ do the same, and go to the *previous*
or *next* line's edge when the caret is already on the edge they would land on,
so a run of them steps through the file. ⇧⌃A, ⇧⌃E, ⌥⇧↑ and ⌥⇧↓ are those four
with the text between selected: Shift decides only whether it comes along, and
nothing else about where the caret lands.

**The start of the line means column zero, and not the first non-blank
character.** ⌘← is the key that stops at the indent first and goes to column
zero on a second press; ⌃A and ⌥↑ do not, and the difference is not a
preference. macOS sends ⌥↑ as two selectors in order — one character back,
then to the start of the paragraph — and the leading step is what makes the key
reach the previous line from a line's start. A stop that decided where to go by
reading where the caret already is would read that intermediate position as if
somebody had typed it, and on an indented line would send the caret back to
where the key started. So the paragraph motions are a function of the position
and never a toggle over it.

⌃D is not one of these keys. `deleteForward:` is the editor's and ⌦ sends it,
but ⌃D is Run ▸ Debug's, and a menu key equivalent is asked before the text
view is.

### Scenario: ⌃A and ⌃E in the middle of a line

- **Given** the caret at offset 53, which is column 6 of `third line of the file`, a line running from 47 to 69
- **When** ⌃A is pressed
- **Then** the caret is at offset 47 and nothing is selected
- **And** ⌃E from offset 53 puts it at 69, also with nothing selected

### Scenario: ⌃A on an indented line

- **Given** the caret at column 11 of `    fourth line, indented four spaces`, a line whose first non-blank character is at offset 74 and which starts at offset 70
- **When** ⌃A is pressed
- **Then** the caret is at offset 70, not at 74
- **And** ⌃A pressed again leaves it at 70

### Scenario: ⇧⌃A and ⇧⌃E take the line with them

- **Given** the caret at offset 53, column 6 of `third line of the file`
- **When** ⇧⌃A is pressed
- **Then** the caret is at offset 47 and `third ` is selected
- **And** ⇧⌃E from offset 53 puts the caret at 69 with `line of the file` selected

### Scenario: ⌥↑ and ⌥↓ from the middle of a line

- **Given** the caret at offset 53, column 6 of the line running from 47 to 69
- **When** ⌥↑ is pressed
- **Then** the caret is at offset 47
- **And** ⌥↓ from offset 53 puts it at 69

### Scenario: ⌥↑ from the start of a line, and ⌥↓ from the end of one

- **Given** the caret at offset 47, the start of `third line of the file`
- **When** ⌥↑ is pressed
- **Then** the caret is at offset 23, the start of the line above
- **And** ⌥↓ from offset 69, the end of that same line, puts the caret at 107, the end of the line below

### Scenario: ⌥↑ from the first non-blank of an indented line

- **Given** the caret at offset 74, the `f` of `    fourth line, indented four spaces`
- **When** ⌥↑ is pressed
- **Then** the caret is at offset 70, the start of that line

### Scenario: ⌥⇧↑ takes a whole line at a boundary

- **Given** the caret at offset 47, the start of `third line of the file`
- **When** ⌥⇧↑ is pressed
- **Then** the caret is at offset 23 and `second line of the file` and its newline are selected

## ADDED Requirement: ⌃K deletes to the end of the line and leaves the newline

⌃K takes everything from the caret to the end of the line it is on and leaves
the caret where it was. The line break is the *boundary* of a paragraph rather
than part of one, so ⌃K stops in front of it: pressed at the end of a line it
takes nothing at all, and it never joins two lines into one.

That makes ⌃K the same deletion as ⌘⌦, reached by a different key, and it is
deliberately not emacs's `kill-line`, which takes the newline on a second
press.

### Scenario: ⌃K in the middle of a line

- **Given** the caret at offset 53, column 6 of `third line of the file`
- **When** ⌃K is pressed
- **Then** the line is `third `, the caret is still at offset 53, and nothing is selected

### Scenario: ⌃K at the end of a line

- **Given** the caret at the end of `    fourth line, indented four spaces`
- **When** ⌃K is pressed
- **Then** nothing changes: that line and the one below it are still two lines
