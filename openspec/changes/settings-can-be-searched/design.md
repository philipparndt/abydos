## Context

The settings window is one page, `SettingsPage`, built from
`SettingsPaneController.Row` lists — one `Section` per subject in a shared
list, each row a title, an optional sentence of help and a control. It replaced
a toolbar-style `NSTabViewController` because that shape cannot show a page
under a page, and Tools had grown children. One page, one order, one place to
add a setting — and one long page to find a row in.

`SettingsPaneController.describe(_:withHelp:)` already flattens a row list to
its titles and help for the driven checks, which is the same walk a filter
needs.

## Decisions

**Filter, not search.** A field that narrows the page in place, rather than a
results list that opens the section on click. A results list is a second
navigation over one list, which is the drift the shared section list exists to
prevent; a filter is the page itself, shorter.

**Title and help both match.** The sentence under a control is where the words
people search with actually are — "Engine" is found by "ghostty" only through
its help. Matching titles alone would make the field look broken for exactly
the settings somebody cannot find.

**Every word, anywhere, case-insensitively.** "tmux status" should find the
row about tmux's status bar whether the title says "status" and the help says
"tmux" or the other way round. Substring, not prefix: "engine" should match
"Terminal engine".

**Section headings stay.** A row shown without its section reads as a row from
nowhere; a section shown with none of its rows is noise. So a heading is shown
when at least one of its rows is, and hidden otherwise.

**Nothing moves.** Filtering hides views; it does not rebuild the page, so the
controls keep their state and their targets, and clearing the field is
un-hiding. `isHidden` on the row's container view rather than removing it.

*Ruled out: fuzzy matching.* Nice for a command palette with hundreds of
verbs; over a few dozen settings rows it finds rows people did not mean and
cannot be explained in a sentence.

*Ruled out: a search field in the toolbar.* There is no toolbar — that was the
point of the one-page shape.

## Risks / Trade-offs

**A group row's children** → `Row.group` nests rows; the match walks into
groups and shows the group's heading when a child matches, as with sections.

**Help that is a paragraph** → matching over long help finds more than people
expect. Accepted: the match is visible on the page, since the help is shown
under the row.

## Open Questions

- Whether ⌘F in the settings window should focus the field. Probably; decided
  when it is built.
