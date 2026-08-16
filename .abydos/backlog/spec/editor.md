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
