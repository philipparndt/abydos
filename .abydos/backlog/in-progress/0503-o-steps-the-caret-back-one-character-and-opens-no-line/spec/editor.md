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

     One ADDED, and no MODIFIED of 0497's requirement even though its last
     paragraph — "the rest of the emacs family is not this requirement" —
     names ⌃P and ⌃N and could name ⌃O too. Two reasons. The sentence is
     not made untrue by this item: ⌃O is still not that requirement, it is
     this one, and a heading exists to be found rather than to be listed
     from every neighbouring heading. And 0502 is in another worktree this
     week adding the paragraph selectors, which is exactly the family that
     paragraph is about; two deltas rewriting the same requirement in the
     same week is a conflict bought for nothing.

     Not corrected here either: the same requirement says a letter with a
     combining mark is one step of ⌃F, and it is two. That is 0504 — the
     sentence describes what the editor should do, so the item that makes
     it true owns it, and a MODIFIED here would only record the bug in the
     place the spec keeps its promises.

     The requirement is about ⌃O and not about "keys that insert a line",
     because Return is not in the spec at all yet and inventing a heading
     for both would put a requirement in front of behaviour nobody has
     written down. What it does say, and the reason it is worth a
     requirement rather than a line, is *why the indent is not copied*:
     that is the decision this item was filed to make, and the next person
     to add automatic indentation to something will otherwise make the
     other choice for good-looking reasons.
-->

## ADDED Requirement: ⌃O opens a line under the caret and leaves the caret alone

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
