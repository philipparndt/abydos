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
       ⌃A and ⌃E go to the ends of the line, and so do ⌥↑ and ⌥↓
       ⌃K deletes to the end of the line and leaves the newline
       ⌃O opens a line under the caret and leaves the caret alone
-->

## ADDED Requirement: A selection is drawn gray while the keyboard is somewhere else

Selected text in an editor pane is drawn in the strong highlight only while that
pane has the keyboard. With the keyboard anywhere else — the terminal below, a
results list, another pane of a split — the same selection is still there and is
drawn gray.

A selection in the strong colour is a claim that the next key will act on it, and
a claim a view makes whether or not it is true is worth nothing. The gray is one
colour for the whole program: an editor's selected text, a row of a results list
and a row of the project tree all go to the same one, so a window whose keyboard
is in the terminal gives the same answer in every pane at once.

The selection is not cleared and nothing else about it changes. It comes back to
the strong colour the moment the pane has the keyboard again, and it is the same
characters that were selected before.

### Scenario: the keyboard goes to the terminal

- **Given** several lines selected in an editor pane
- **When** the keyboard moves to the terminal below it
- **Then** the same lines are still selected, drawn gray

### Scenario: and comes back

- **Given** that gray selection
- **When** the editor pane is clicked
- **Then** the same lines are selected in the strong highlight again

### Scenario: two panes of a split

- **Given** two editor panes, each with a selection
- **When** one of them has the keyboard
- **Then** only that pane draws its selection in the strong highlight
