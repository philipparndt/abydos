# Editor

## Requirement: ⌘/ comments out the lines a selection touches

Edit ▸ Toggle Comment, which is ⌘/, comments out every line the selection
touches, or the caret's line when nothing is selected. Pressed again over the
same lines it takes the comment off, so two presses leave the file exactly as
they found it. The whole press is one undo, however many lines it was.

The direction is decided for the block and not per line: if every non-blank line
in the range already carries the language's line comment the press uncomments,
and otherwise it comments all of them. Toggling each line on its own would turn a
half-commented block into its inverse, which is not something anybody wants
twice.

### Scenario: three lines, none of them commented

- **Given** three lines of Swift selected, none commented
- **When** ⌘/ is pressed
- **Then** each of them begins with `// `

### Scenario: the same three lines again

- **Given** those three lines still selected
- **When** ⌘/ is pressed a second time
- **Then** the file is byte for byte what it was before the first press

### Scenario: a block where somebody had already commented one line

- **Given** three lines selected and the first of them already `// one`
- **When** ⌘/ is pressed
- **Then** all three are commented, the first of them twice

## Requirement: the comment goes at the indent the lines share

The token is inserted at the shallowest indentation every non-blank line in the
range has in common, not at column zero, so commenting an indented block leaves
the shape of the code somebody was reading it by. What is shared is the longest
common *prefix* of those lines' indentation rather than the smallest visual
width: a width can name a column that falls inside a tab on one line and between
two spaces on another, and a prefix is by construction a position every one of
those lines has.

Uncommenting takes the token off wherever it is on each line rather than at the
shared indent, so a file commented by another editor at column zero uncomments.

### Scenario: a function body indented one tab further than its signature

- **Given** a Swift function selected, its signature at one tab and its body at two
- **When** ⌘/ is pressed
- **Then** every line reads one tab, then `// `, then what it read before

### Scenario: a Makefile target and its recipe

- **Given** `build:` and a recipe line beginning with a tab, both selected
- **When** ⌘/ is pressed
- **Then** both begin with `# `, the recipe's tab now after it

### Scenario: one line indented with a tab and the next with spaces

- **Given** two lines selected, the first indented with a tab and the second with spaces
- **When** ⌘/ is pressed
- **Then** the token is at column zero on both, and neither indent is split

## Requirement: blank lines are neither commented nor counted

A blank line inside the range is left exactly as it is — a `//` on an empty line
is trailing rubbish — and it does not count towards whether the range is already
commented. One empty line in the middle of a commented block therefore does not
flip the press back to commenting it again. A range of nothing but blank lines is
left alone.

Uncommenting removes exactly what commenting inserted: the token, and the single
space after it only when there is one. A line whose author wrote `//code` comes
back as `code` and never as ` code`.

### Scenario: a commented block with an empty line in it

- **Given** two commented lines with an empty line between them, all selected
- **When** ⌘/ is pressed
- **Then** both are uncommented and the empty line is still empty

### Scenario: a comment written without a space

- **Given** the line `//code` selected
- **When** ⌘/ is pressed
- **Then** the line reads `code`

## Requirement: the selection still covers the same text afterwards

After a press the selection covers the same characters it covered before, moved
by whatever went in in front of them, so a second ⌘/ acts on the same lines as
the first. A selection of whole lines stays a selection of whole lines: its start
keeps the front of its first line even when the token was inserted there. A caret
with nothing selected keeps its place relative to the text, which means it ends
up in front of the code rather than in front of the token it now sits behind.

### Scenario: a caret in the middle of a line

- **Given** a caret immediately before `a` in `let a = 1`
- **When** ⌘/ is pressed
- **Then** the line reads `// let a = 1` and the caret is still immediately before `a`

### Scenario: two whole lines of a Makefile

- **Given** two whole lines selected in a Makefile, the token going at column zero
- **When** ⌘/ is pressed
- **Then** both whole lines are still selected, the inserted `# ` included

## Requirement: a language with no line comment says so rather than nothing

Every language this editor can resolve a file to has an answer for ⌘/: a token,
or a sentence saying why there is none. CSS, HTML and the XML shown through it,
Markdown, Svelte and JSON have no line comment — `/* */` and `<!-- -->` do not
nest, so wrapping each line would mangle a line that already carried one — and
JSON has no comment of any kind. In those files ⌘/ changes nothing and says why
in the corner, once per press. A file of no recognised language says that instead
of guessing a token, because a `#` in a file that turns out to be C is a syntax
error somebody then has to find.

A language whose grammar is missing still has a token. The table is keyed on the
same language ids a file is resolved to everywhere else, so `.puml` gets `'`
although no PlantUML grammar is vendored, and a file whose query bundle failed to
load comments out as usual.

### Scenario: a stylesheet

- **Given** two lines of CSS selected
- **When** ⌘/ is pressed
- **Then** the file is unchanged and the corner says CSS has only `/* … */`

### Scenario: a `package.json`

- **Given** two lines of JSON selected
- **When** ⌘/ is pressed
- **Then** the file is unchanged and the corner says JSON has no comments

### Scenario: a PlantUML diagram, for which there is no grammar

- **Given** a line of a `.puml` file selected
- **When** ⌘/ is pressed
- **Then** the line begins with `' `

## Requirement: an embedded language gets its host's comment, not its own

A `<script>` inside HTML, a `<style>` inside Svelte and a fenced code block
inside Markdown are read with the inner language's grammar for colour, and ⌘/
does **not** follow them: the answer comes from the file's own language and
nothing else. So ⌘/ inside a Markdown fence of Swift refuses, saying Markdown has
no line comment, rather than inserting `//`.

This is a limit and not a decision about those languages. Which language a
*range* is in has no answer in this editor yet; only which language a file is in
does. Rather than answer `//` for a whole `.svelte` file and put it in the middle
of the markup, those languages refuse and say what they have instead.

### Scenario: a Swift fence inside a Markdown file

- **Given** a line inside a ```` ```swift ```` block selected
- **When** ⌘/ is pressed
- **Then** the file is unchanged and the corner says Markdown has no line comment

## Requirement: ⌘/ is ⌘/ on every keyboard

Edit ▸ Toggle Comment reads **⌘/** whatever the keyboard is set to, and the press
is whatever makes a `/` on that keyboard — ⌘/ where the slash is unshifted, ⌘⇧7
on a German layout, and so on. It is the shortcut every editor documents, and a
person told "⌘/" finds it in the menu spelled that way.

macOS would otherwise move it. The system relocates a key equivalent it judges
awkward on the current layout to one needing no shift, and on a German keyboard
that put Toggle Comment on **⌘ß** — a key nobody would try for commenting, while
⌘⇧7 reached nothing at all. So this one item keeps its literal key.

**Only this one.** Every other shortcut in the app is still the system's to move,
and is better for it: `[`, `]`, `\` and `=` all need ⌥ on a German keyboard, and the
system puts them on the key in the same place a US keyboard has them — Back and
Forward read ⌘Ö and ⌘Ä there, and answer to them, rather than needing ⌥⌘5 and ⌥⌘6.
Every shortcut in the menu bar is reachable by the press the menu shows.

### Scenario: a German keyboard, where a slash is a shifted 7

- **Given** the keyboard layout is German
- **When** the Edit menu is opened
- **Then** Toggle Comment reads ⌘/

### Scenario: pressing it on that keyboard

- **Given** a Swift file open on a machine with a German layout
- **When** ⌘⇧7 is pressed, which is how a `/` is typed there
- **Then** the caret's line is commented out

### Scenario: the slash on a numeric keypad

- **Given** the same file, and a keyboard with a numeric keypad
- **When** ⌘ and the keypad's `/` are pressed
- **Then** the caret's line is commented out, the same as ⌘⇧7 does

### Scenario: a shortcut whose key needs option on that keyboard

- **Given** the same keyboard, on which `[` is typed with ⌥5
- **When** the Edit menu is opened
- **Then** Back reads ⌘Ö, the key where `[` is on a US keyboard, and answers to it

## Requirement: ↑ on the first line and ↓ on the last go to the edge of the file

A vertical key with no row to move to takes the caret to that end of the
document rather than doing nothing: ↑ anywhere on the first line goes to offset
zero, ↓ anywhere on the last goes to the end of the file. Page Up and Page Down
are the same motion with a screenful as the step, so a page that overshoots
lands on the edge too — in a file shorter than the window, Page Up is the start
of the file and Page Down its end.

This is what every other text view on the machine does, and it is what makes
the keys feel alive at the ends of a file: clamping the row to the document
gives back the row the caret is already on, which is a keystroke that does
nothing at all.

The column a run of ups and downs is keeping survives the jump. ↓ off the end
and then ↑ comes back to the column the run started at, not to the column the
last line happens to end at.

With soft wrap on the motion is by *row* and not by line, so the first ↑ from
partway along a wrapped first line is the row above it, still inside that line;
only running out of rows is the start of the file.

### Scenario: the caret in the middle of the first line

- **Given** a file whose first line is `one word001 word002 …`, the caret at column 8
- **When** ↑ is pressed
- **Then** the caret is at offset 0 and nothing is selected

### Scenario: the caret in the middle of the last line

- **Given** the caret at column 4 of the last line, which ends at offset 863
- **When** ↓ is pressed
- **Then** the caret is at offset 863 and nothing is selected

### Scenario: a file shorter than the window

- **Given** a file of seven lines, the caret on the first of them
- **When** Page Up is pressed
- **Then** the caret is at offset 0

### Scenario: partway along a wrapped line, with soft wrap on

- **Given** a first line long enough to wrap into four rows, the caret at column 400 of it
- **When** ↑ is pressed
- **Then** the caret is one row up and still inside the first line, at the same column
- **And** ↑ again takes it to offset 0

## Requirement: Shift takes the selection to the edge with it

Shift decides only whether the selection comes along, and nothing else about
where the caret lands. ⇧↑ on the first line selects from the caret back to the
start of the file, and ⇧↓ on the last selects from the caret to the end of it —
which on those two lines is the same thing as selecting to the start or the end
of the line, since the two offsets coincide. ⇧⇞ and ⇧⇟ do the same with a
screenful as the step.

⌘⇧↑ and ⌘⇧↓ do it from anywhere. ⌘↑ and ⌘↓ are the jump to the start and the
end of the document — not a key that ran out of rows, but the motion whose
whole purpose is the edge — and they are the same motion from the middle of a
file as from either end of it. Holding Shift changes only that the text between
where the caret was and where it lands is selected, so from halfway down a file
⌘⇧↑ selects everything above the caret and ⌘⇧↓ everything below it.

Soft wrap makes no difference to those two. Every other key in this
requirement moves by rows, and a row is a wrapped segment rather than a line;
the jump to the ends of the document is offsets and never asks about a row.

### Scenario: ⇧↑ on the first line

- **Given** a file whose first line begins `one word001`, the caret at column 8
- **When** ⇧↑ is pressed
- **Then** the caret is at offset 0 and `one word` is selected

### Scenario: ⇧↓ on the last line

- **Given** the caret at column 4 of the last line, `seventh and last line of the file`
- **When** ⇧↓ is pressed
- **Then** the caret is at the end of the file and `nth and last line of the file` is selected

### Scenario: ⇧⇟ on the last line

- **Given** the caret at column 4 of the last line of a file shorter than the window
- **When** ⇧⇟ is pressed
- **Then** the selection reaches the end of the file, as ⇧↓ does

### Scenario: ⌘⇧↑ from the middle of a file

- **Given** a file of seven lines ending at offset 863, the caret at column 4 of line 3, which is offset 775
- **When** ⌘⇧↑ is pressed
- **Then** the caret is at offset 0 and everything from 0 to 775 is selected

### Scenario: ⌘⇧↓ from the middle of a file

- **Given** the same file and the same caret at offset 775
- **When** ⌘⇧↓ is pressed
- **Then** the caret is at offset 863 and everything from 775 to 863 is selected

### Scenario: ⌘↑ and ⌘↓ without Shift, from the same place

- **Given** the same file and the same caret at offset 775
- **When** ⌘↑ is pressed, and then, from offset 775 again, ⌘↓
- **Then** the caret lands on offset 0 and then on offset 863, the same two
  places the shifted pair land on, and nothing is selected either time

## Requirement: ⌃B and ⌃F move the caret a character, and so do ← and →

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

A character is what a reader would point at as one — an extended grapheme
cluster — so an emoji, a letter with a combining mark, a ZWJ sequence, an emoji
with a skin-tone modifier and a flag are each one step and not two. **Not a
UTF-8 sequence**, which is what this used to step by and is the difference 0504
turned on: an emoji is one four-byte sequence and moved as one, while `e`
followed by a combining acute is two sequences with two valid starts, so the
caret came to rest between the letter and its mark. The emoji working is what
let that hide for as long as it did.

Deleting asks the same question. ⌫ and ⌦ each remove one whole character, so no
keystroke can leave a combining mark without its base letter — before this they
had two more copies of the byte walk between them, and ⌫ after a decomposed `é`
took the accent and left the `e`.

At the start of a line the character before the caret is the newline that ended
the line above, so ⌃B goes to the end of that line; at offset zero there is
nothing to step over and the caret stays. A `\r\n` pair is one character, so
nothing can land between the two halves of it.

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

### Scenario: ⇧⌃F over a decomposed accent

- **Given** the caret at offset 14, with `e` followed by U+0301 in front of it
- **When** ⇧⌃F is pressed
- **Then** the caret is at offset 16 and the whole `é` is selected
- **And** ⌃F alone from 14 puts the caret at 16, not at 15

### Scenario: ⌃F over a ZWJ sequence

- **Given** the caret at offset 14, with `👨‍👩‍👧` in front of it
- **When** ⇧⌃F is pressed
- **Then** the caret is at offset 22 and the whole sequence is selected, not the
  first person in it

### Scenario: ⌫ after a decomposed accent

- **Given** the caret immediately after `e` + U+0301
- **When** ⌫ is pressed
- **Then** both the letter and its mark are removed, leaving no orphaned mark

### Scenario: ⌃B at the start of a line

- **Given** the caret at column 0 of the third line, which is offset 44
- **When** ⌃B is pressed
- **Then** the caret is at offset 43, the end of the line above

### Scenario: ⌃B at the start of the file

- **Given** the caret at offset 0
- **When** ⌃B is pressed
- **Then** the caret is still at offset 0 and nothing is selected

## Requirement: ⌃A and ⌃E go to the ends of the line, and so do ⌥↑ and ⌥↓

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

## Requirement: ⌃K deletes to the end of the line and leaves the newline

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

## Requirement: ⌃O opens a line under the caret and leaves the caret alone

⌃O is `open-line`: it splits the line at the caret and does not move the
caret. What was in front of the caret stays where it is; what was behind it
becomes the next line; the caret stays between them, at the end of the first
half. Pressing it repeatedly pushes the rest of the line further down the
file and never moves the caret off the character it was on.

macOS sends ⌃O as **two** commands in order — insert a newline, then step back
one character — and the editor answers the first with a **bare** newline. It
does not copy the indent of the line it splits, and the second half is not
re-indented, so on an indented line the line that appears is empty rather than
full of whitespace.

That is a decision about what open-line is, and it is what makes the two
commands cancel. The step back is one character, so the caret returns to where
it started only if the insertion moved it by exactly one. An indent-copying
newline would move it by one plus the indent and leave the caret inside
whitespace it had just written — on a line the caret is deliberately not
being moved to. Return is the key that carries the indent, because Return puts
the caret on the new line and somebody is about to type there; ⌃O does not,
so it does not.

The caret keeps its offset, not its column, and after the split those are the
same thing: the text before it is unchanged.

### Scenario: ⌃O with the caret in the middle of a word

- **Given** the line `third li|ne of the file` with the caret at offset 51, after the `i`
- **When** ⌃O is pressed
- **Then** the line reads `third li`, the next line reads `ne of the file`
- **And** the caret is still at offset 51, at the end of the first half

### Scenario: ⌃O at the end of an indented line

- **Given** a line indented with a tab, `→indented fifth line of the file`, the caret at its end
- **When** ⌃O is pressed
- **Then** an empty line appears after it — empty, with no copy of the tab
- **And** the caret is still at the end of the indented line, at the same offset

### Scenario: ⌃O on an empty line

- **Given** the caret on an empty line, with `sixth lines` on the line below
- **When** ⌃O is pressed
- **Then** there are two empty lines and `sixth lines` has moved down one
- **And** the caret is still on the first of them, at the same offset

## Requirement: A selection is drawn gray while the keyboard is somewhere else

Selected text in an editor pane is drawn in the strong highlight only while that
pane has the keyboard. With the keyboard anywhere else — the terminal below, a
results list, another pane of a split — the same selection is still there and is
drawn in a quiet colour instead.

A selection in the strong colour is a claim that the next key will act on it, and
a claim a view makes whether or not it is true is worth nothing. One rule decides
it everywhere — an editor's selected text, a row of a results list and a row of
the project tree all ask the same question — so a window whose keyboard is in the
terminal gives the same answer in every pane at once.

**The quiet colour is not one colour, because a row and a run of text need
different amounts of lift from the same ground.** A row is a band the width of
the pane with an edge above and below it; selected code is a ragged shape mostly
covered by the glyphs sitting on it, and the same colour that reads as a band on
a row disappears behind code. So a row goes to the scheme's `selectionInactive`,
which is what the project tree has used for years, and an editor's text goes to
its `selectionBackgroundInactive`, which every scheme states for itself and which
sits below its own strong highlight — quiet enough not to be mistaken for the
keyboard being here, and never so quiet that a selection has to be looked for.

A scheme that does not state one still gets one: halfway between the two it sits
between, `selectionInactive` and `selectionBackground`. It is the only colour in
a scheme file that may be left out.

The selection is not cleared and nothing else about it changes. It comes back to
the strong colour the moment the pane has the keyboard again, and it is the same
characters that were selected before.

### Scenario: the keyboard goes to the terminal

- **Given** several lines selected in an editor pane
- **When** the keyboard moves to the terminal below it
- **Then** the same lines are still selected, drawn in the quiet colour, and the
  band is still visible against the code it covers

### Scenario: and comes back

- **Given** that quiet selection
- **When** the editor pane is clicked
- **Then** the same lines are selected in the strong highlight again

### Scenario: two panes of a split

- **Given** two editor panes, each with a selection
- **When** one of them has the keyboard
- **Then** only that pane draws its selection in the strong highlight

### Scenario: a row and a run of text in the same window

- **Given** a selected row in the project tree and selected text in an editor,
  with the keyboard in neither
- **Then** the row is drawn in `selectionInactive` and the text in
  `selectionBackgroundInactive`, which is the scheme's stronger of the two

## Requirement: A place the editor is sent to is on the screen when it gets there

Something outside the editor — a search result, a usage, a review finding, a
symbol from the palette, `abydos main.go:214`, the line a debugger stopped on —
asks for a place in a file, and the editor shows it. Showing it means it is
**within the pane** when the scrolling stops, both down the page and across it.

The pane is measured, not guessed. Everything the answer is worked out from is a
property of a laid-out view — where a line falls once folding and soft wrap are
accounted for, how tall the viewport is, how wide the text column is inside its
gutter — so the reveal makes the layout pass happen before it measures, rather
than running a turn of the main loop later and hoping it has. A turn of the main
loop is not "the pane has been laid out"; it is a turn of the main loop, and a
reveal that bets on one is right most of the time and wrong the rest, which is
what "sometimes off the screen" was.

Where there is still nothing to measure — a tab whose window is not on screen
yet, a pane the layout pass has not reached — the reveal **waits for the pane to
be given a size** and happens then. It does not scroll to a position computed
from a viewport of no height, and it does not retry on a timer: what it waits for
is the event that means "you have a size now".

**Vertically**, a line that has to be brought in is centred, so there is context
around what was jumped to. A line that is already on screen is shown by leaving
the view where it is — with the top row and the bottom two counting as off screen,
because a line drawn half over an edge is not one anybody can read.

**Horizontally**, what is being pointed at is brought inside the text column with
a little context beside it, and the offset is left alone when it is already
inside. This is not "scroll to the column": a match eighty characters along its
line does not push the start of that line off the left edge for no reason. Text
under the gutter counts as off the screen, because the gutter is drawn over the
viewport's left edge rather than over the text. Where soft wrap is on there is
nothing to scroll sideways and the pane stays against the left edge.

A match is a **span and not a point**: how wide it is comes with it, so one that
starts a column inside the right edge and runs past it is brought in rather than
called visible on the strength of its first character. One longer than the pane
is wide is shown from its start, because what is read is read from the beginning.

### Scenario: a search result in a file that has just been opened

- **Given** a result in a file with no tab open, in a project search
- **When** the row is shown
- **Then** the file opens, the caret is on the match, and the match is inside the
  pane — however many turns of the main loop the opening took

### Scenario: walking a file's matches with ↓

- **Given** three matches within a screenful of each other
- **When** the selection is moved onto each of them in turn
- **Then** the first is brought on screen and the view does not move again for the
  other two

### Scenario: a match far along a long line

- **Given** a match at column 262 of a 294-character line, in a pane about a
  hundred columns wide
- **When** it is revealed
- **Then** the pane is scrolled sideways until the match and some of what follows
  it are visible, and the whole match is on the screen rather than its first
  character

### Scenario: a match already visible on a long line

- **Given** a pane scrolled sideways, with the next match inside the text column
- **When** that match is revealed
- **Then** neither offset changes

### Scenario: a reveal asked for before the pane has a size

- **Given** a reveal on a pane whose viewport has no height yet
- **When** the pane is given its size
- **Then** the place asked for is brought on screen at that moment, and nothing
  was scrolled in the meantime

## Requirement: A file dropped on the editor opens in it

A file dragged onto an editor group — from the Finder, from another application,
from the project tree — opens in that group, in a tab, exactly as opening it any
other way does. The whole group is the target, not only the tab strip: the text
is where somebody is looking when they decide to drop something.

The editor registered one dragged type, `EditorTabDrag.pasteboardType`, so a drag
carrying a file was never offered to the window at all. It was not refused; it
was not seen.

**The operation offered is one the drag permits.** An external file drag offers
copy, and the drop view answered `.move` to everything — right for a tab moving
between panes, and exactly what the Finder does not offer. The project tree
already carries the lesson: an operation the source never permitted is a drop
that quietly does nothing, indistinguishable from not accepting the drag.

Only file URLs are taken. A browser will put a web address on the drag board and
`NSURL` reads it perfectly well; a tab named after a website is worse than a drag
that springs back.

Several files open several tabs, in the order dropped, last in front, none of
them provisional — a preview tab is the answer to a single click, and a drag is
deliberate.

**The window's project does not change.** The tree, git, the run configurations,
the language servers and the remembered session all belong to it, so re-pointing
them because somebody dragged a file in is a very large answer to a very small
gesture. A file dropped on the *Dock icon* is a different case and does switch:
that one is addressed to the application, which has no window in mind and must
find one.

**A folder is a project**, which is what a folder means everywhere else here, so
it goes through the same opening as `abydos <dir>` and the switcher — the same
setting about taking this window or another, and the same raising of a window
already on it.

A drag holding both opens the folders first and the files into the window that
results. The other order was measured and lost the file: opened into the project
being left, it was discarded when switching restored the arriving project's
session.

The zone overlay stays a tab's business. It answers "where does this pane go", and
a file is a tab rather than a pane, so a file over the group highlights nothing —
what is shown is what will happen.

### Scenario: a file from another checkout

- **Given** a window open on one project
- **When** a file belonging to a different checkout is dropped on the editor
- **Then** it opens in a tab, and the window is still on the project it was on

### Scenario: several at once

- **When** three files are dropped together
- **Then** three tabs open, in that order, with the last in front

### Scenario: a folder

- **When** a folder is dropped
- **Then** it opens as a project

### Scenario: a folder and a file together

- **When** both are dropped in one drag
- **Then** the folder opens as a project and the file is open in that window

### Scenario: something that is not a file

- **When** a web address is dragged onto the editor
- **Then** nothing opens

### Scenario: a tab is still a tab

- **When** a tab is dragged onto a group's right-hand zone
- **Then** the group splits, as it did before the editor took files

## Requirement: Find belongs to the tab it searched

The find bar's state belongs to the tab it was opened in — whether it is
showing, what is being looked for, which switches are set, the matches, and which
one is current. One bar serves the whole group; what it shows is the tab in
front's.

This is what the rest of the editor already does and says it does: each tab owns
its own `CodeView`, so caret, selection, scroll offset and folds survive a tab
switch because they were never shared. Find was the exception — one flag and one
list of matches for every tab in the group. So opening find in one file opened it
in all of them, and **the matches were a different file's**: they are UTF-16
offsets into one document, and stepping after a tab switch handed them to another
document's view, which sets a caret from them.

Measured, with the fix in: a 199-match search in a 4071-unit file, then the
5-unit file selected — stepping moves nothing, and coming back to the first tab
restores its query, its 199 matches, its current index and its caret at 13.

Closing a tab takes its find state with it, and a tab moved to another group
takes it along, because the state is on the tab.

### Scenario: find open in one tab

- **Given** two files open in one group
- **When** find is opened in the first and the second is selected
- **Then** the second shows no find bar

### Scenario: stepping after a tab switch

- **Given** a tab searched for a word the tab beside it does not contain
- **When** the other tab is selected and Next is pressed
- **Then** nothing moves in the file that was not searched

### Scenario: coming back

- **When** the searched tab is selected again
- **Then** the bar is showing, with the same query, matches and current match

## Requirement: A search that found nothing says so in red, and so does a pattern that did not run

A search that found nothing says `No results` in red, and a pattern that will not
compile says something else.

The bar already had a red: the query goes `gitConflict` when a regex does not
compile, with a comment saying an unfinished pattern is marked invalid "rather
than reported as 'no results', which would read as a wrong answer". **That was
not true.** An invalid pattern still reached the search, the search found nothing
in a regex that never compiled, and the label a few pixels away said `No results`
anyway. Once red means both "found nothing" and "did not run", the words are the
only thing left to separate them:

| query | label |
| --- | --- |
| empty | *nothing* |
| matches | `3 of 17` |
| no matches | `No results`, red |
| will not compile | `Incomplete pattern`, red |

**The label carries it, not the query text.** Colouring the text was implemented
and measured not to reach the screen: with the field's colour, its field editor's
colour and its attributed string all holding the scheme's red, a capture has the
query white — `(236, 235, 235)` over 1007 glyph pixels — beside a `No results` at
`(212, 114, 112)`. `NSSearchField` paints its text in a colour of its own, and
owning that means replacing the control and drawing its magnifier and clear
button by hand.

The red is the scheme's own `gitConflict` and not a role of its own: a required
`SchemeRole` that a file lacks refuses the whole file, and schemes are files
people keep in dotfiles repositories.

A pattern that does not compile is not searched for, so the matches of the last
query that did compile stay on screen rather than being cleared by a keystroke
that was half of a bracket.

### Scenario: nothing found

- **When** a query matches nothing
- **Then** `No results` is shown in red

### Scenario: half a pattern

- **Given** find in regex mode
- **When** `(` is typed and no more
- **Then** the bar says the pattern is incomplete, and does not say `No results`

### Scenario: an empty query

- **When** the query is cleared
- **Then** nothing is red and nothing is said

## Requirement: The current find match is the loudest thing on the page

Find in a file highlights every match on screen, and the one being looked at —
the one the counter says is 2 of 3, the one ⌘G moves — is drawn more strongly
than the rest. That is the whole reason there is a current match: a page of
identical bands answers "where are they" and not "where am I".

**It stays the loudest whatever else lands on the same characters.** Revealing a
match selects it, so the current match is also a selection, and a selection is
drawn over the line's background — which used to mean the strongest highlight in
the file was covered by one of the quietest colours in the scheme, and the match
somebody was reading became the darkest of the three on the screen. The current
match is therefore painted **after** the selection rather than before it. Which
of the two claims wins where they coincide is decided, rather than falling out of
the order two pieces of drawing code happen to run in.

Only the match's own rectangle is covered. A selection wider than the match — one
somebody extended, or a selection of whole lines — is still drawn in full, and
still reads as a selection either side of the match sitting on it.

This holds in both keyboard states. While a query is being typed the editor has
not got the keyboard and the selection is the scheme's quiet colour; with the
keyboard back in the code and ⌘G stepping on it is the strong one. Neither is
loud enough to matter, because neither is on top.

### Scenario: three matches on adjacent lines, the keyboard in the find field

- **Given** a file with three matches of the same word on consecutive lines
- **When** the find bar is open with that query and the first match is current
- **Then** the current match is drawn more strongly than the other two, which are
  drawn more strongly than the unhighlighted code

### Scenario: the keyboard back in the editor

- **Given** those three matches with the current one selected
- **When** the keyboard is in the editor and ⌘G steps to the second
- **Then** the second is now the strong one and the first has gone back to the
  quiet match colour

### Scenario: a selection wider than the match

- **Given** the current match on a line, and a selection of that line and the two
  below it
- **Then** all three lines are drawn as a selection, and the current match is
  drawn on top of its own characters within it

## Requirement: The find highlights are the scheme's colours

Both match colours belong to the scheme file — `searchMatchCurrentBackground` for
the one being looked at, `searchMatchBackground` for the rest — stated at both
lightnesses like every other colour a window is painted in. They were fixed in
the drawing code until this was written, chosen against one dark warm ground,
which is what every light scheme drew its find highlights in.

A scheme may leave either out, as it may leave `selectionBackgroundInactive` out
and for the same reason: they arrived after schemes were already files somebody
keeps. A file that says nothing gets a stated derivation rather than a silent
default — the current match halfway between `selectionBackground` and `caret`,
the other matches halfway again back towards `selectionBackground` — so a scheme
nobody has looked at cannot end up with the matches nobody is reading louder than
the one they are.

Every scheme the app ships states both. The rule they are judged against is that
the current match has more contrast against `editorBackground` than the other
matches *and* than either selection colour, since the current match is also the
selection and nothing that can land on the same characters may take the eye off
it.

### Scenario: a light scheme

- **Given** any of the shipped schemes at its light lightness
- **Then** its find highlights are its own colours, and the current match is the
  more contrasting of the two against its editor background

### Scenario: a scheme file that does not mention them

- **Given** a personal scheme written before these keys existed
- **Then** it loads, and its current match is halfway between its selection and
  its caret, with the other matches halfway between its selection and that

## Requirement: The side buttons go back and forward

A mouse's side buttons move through the navigation history — button 3 back,
button 4 forward — and it is the history ⌘[ and ⌘] move through, not a second
one. The same rules about when a step is possible, and the same handling of a
file deleted since, because it is the same two functions the menu items call.

**They were never wired.** `navigateBack` and `navigateForward` worked and every
caller of them was a menu item; nothing read a mouse button. Reported as having
worked before, which it may well have — a driver that maps side buttons to ⌘[
and ⌘] makes it work without this app knowing, and stops the day the mapping
changes.

They work wherever the pointer is: over the editor, the tree, the panes and the
terminal. **The window handles them**, so no view has to opt in, and a view that
wants a side button for something of its own can still take it first, which is
what the responder chain is for.

**Acted on the release, not the press.** A navigation changes what is on screen,
and a button held while the hand is still deciding should not have moved
anything — the same reason a click is a press and a release in one place. The
press is consumed so that nothing else sees a stray one.

Where there is nowhere to go the button does nothing, which is the answer the
menu items already give by being disabled.

### Scenario: back over the editor

- **Given** two files opened one after the other
- **When** the back side button is pressed and released over the editor
- **Then** the editor returns to the first, as ⌘[ would

### Scenario: forward again

- **Given** that step back just taken
- **When** the forward side button is used
- **Then** the editor returns to the second

### Scenario: over the terminal

- **When** the back side button is used with the pointer over a terminal
- **Then** the editor goes back, and nothing is sent to the program in the
  terminal

### Scenario: nowhere to go

- **Given** a window with nothing earlier in its history
- **When** the back side button is used
- **Then** nothing happens

