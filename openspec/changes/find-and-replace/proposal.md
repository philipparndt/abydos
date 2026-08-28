# Find and replace

## Why

The find bar finds and cannot replace. ⌘F opens a strip with a query, three
switches — match case, whole word, `.*` — and a count; there is nowhere to type
what the matches should become. Changing forty occurrences of a name in a file
means either forty edits by hand or leaving the editor for `sed`, in a program
whose whole subject is not leaving the editor.

**And the matches do not survive the file being edited.** A capture taken this
morning shows it plainly: `status.md`, searched for a path, then edited to take
that path off eight of its ten lines. The two lines still holding the path are
highlighted correctly. The eight that no longer hold it are highlighted anyway —
bands of the old length at the old offsets, sliding across the text, covering
`delivery-mail.mp4` and `enterprise-admin`, marking matches for a string that is
no longer anywhere on those lines.

Nothing re-runs the search when the text changes. `runFind` is called from the
find field, from a tab coming to the front, and from `⌘G` — and from no edit,
anywhere. The ranges in `Tab.FindState.matches` are UTF-16 offsets into the text
as it was when the search ran, and they are handed to `CodeView.setSearchMatches`,
which draws bands from them **and moves the caret to one of them**. This is the
same class of fault the code already names in `stepMatch` — "one file's offsets
handed to another file's view … a document that never produced that range" —
arriving from the other direction: the same file, a different moment.

It is a fault today, before any of this. It becomes unbearable with replace,
because replacing is editing: every replacement invalidates every match after it,
and a Replace All would leave the file covered in bands that mean nothing.

⌘R is free. The Run menu uses ⌃R for Run and Run…, ⌃⌘R for Go Run, and ⇧⌘R for
Review Branch. The one shortcut every editor uses for replace is unbound here.

## What Changes

- The find bar gains a replace half: a second row with a replacement field, a
  **Replace** button for the current match and a **Replace All**, shown when the
  bar is in replace mode and hidden when it is not. The find half is unchanged
  and stays where it is.
- **⌘R opens the bar in replace mode**, and switches an open find bar to replace,
  putting the keyboard in the replacement field. ⌘F opens or focuses the find
  field and leaves the mode alone, so ⌘R then ⌘F is not a way to lose what has
  been typed. ⎋ closes the whole bar, as it does today.
- **Replace understands the `.*` switch.** With regular expressions on, the
  replacement is a template: `$1` and `$0` mean what the pattern captured. With
  it off, the replacement is literal and `$1` is three characters.
- **Replace All is one undo.** Two hundred replacements that take two hundred
  ⌘Zs to take back are not a replacement, they are a mistake somebody has to
  clean up.
- **The highlights follow the text.** Every edit — typing, a replacement, an
  undo, a file rewritten underneath by an agent or a `git checkout` — moves the
  matches that survive it, drops the ones it destroyed, and asks the question
  again. This is the fix for the fault above and is worth having on its own.
- Replace is offered only where there is something to edit. A PDF tab searches
  through PDFKit and has no text to change; its bar finds and does not replace.

## Capabilities

### New Capabilities
- `replace-in-file`: replacing what find found — the bar's replace half, the
  shortcut that opens it, replacing one match or all of them, what a replacement
  means with regular expressions on and off, and what one undo takes back.

### Modified Capabilities
- `editor`: the find capability it already owns gains the rule it is missing —
  matches belong to the text they were found in, and an edit is not allowed to
  leave them behind. Its existing requirements about find (the current match
  being the loudest thing on the page, find belonging to the tab that searched,
  a search that found nothing saying so) are unchanged.

## Impact

- `FindBar` grows a second row and a mode. It is 309 lines and stays one class:
  the two rows share the query, the switches and the status label, and a replace
  field that did not know the options would be a second place to hold them.
- `EditorViewController` gains the verbs — replace the current match, replace all
  — and the re-run on edit. Its `Tab.FindState` gains the replacement and the
  mode, so both come back with the tab like the query already does.
- `TextSearch` in `AbydosKit` gains the replacement: what one match becomes,
  given a template and the options, and the whole set of edits a Replace All
  makes. That is the part with a test on it, since `Tests/` covers `AbydosKit`
  and nothing in `AbydosApp`.
- `CodeView.onLinesChanged` is the hook the re-run hangs on. It already fires on
  every edit and is already fanned out per tab, which `TextDocument.onTextChanged`
  is not — that one is a single closure the diagram panes assign, and a second
  assignment would silently take the picture away from a `.puml` file.
- No new dependency. Regular expressions are `NSRegularExpression`, which is what
  `TextSearch` already searches with.
