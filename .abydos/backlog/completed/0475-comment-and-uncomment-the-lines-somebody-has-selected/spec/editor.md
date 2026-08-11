<!-- What this item changes about `editor`. Folded into
     .abydos/backlog/spec/editor.md by `abydos-backlog done`.

     Nothing has been said about editor yet, so this is all ADDED.
-->

## ADDED Requirement: ⌘/ comments out the lines a selection touches

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

## ADDED Requirement: the comment goes at the indent the lines share

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

## ADDED Requirement: blank lines are neither commented nor counted

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

## ADDED Requirement: the selection still covers the same text afterwards

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

## ADDED Requirement: a language with no line comment says so rather than nothing

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

## ADDED Requirement: an embedded language gets its host's comment, not its own

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
