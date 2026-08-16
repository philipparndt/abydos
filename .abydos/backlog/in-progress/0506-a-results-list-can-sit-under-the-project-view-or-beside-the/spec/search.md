<!-- What this item changes about `search`. Folded into
     .abydos/backlog/spec/search.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       Search results can be marked done, several at a time
       Marking done is never a deletion, and never wears ⌫
       A mark survives the search being run again
       Marks are hidden on request, so the list can also empty
       ⌘Z in the results list takes back the last marking
       The results list can be worked from the keyboard
-->

## ADDED Requirement: Search results go wherever a usages list goes

The search results are the same checklist the usages list is, so they have the
same four homes and the same **Place** control to choose between them: a tab in
the bottom panel's strip, the lower half of the sidebar under the project view, a
column of the panel beside the terminals, or a window of its own. What each of
them is, what survives a move, which of them hold one list, and where the
keyboard ends up are all said in `usages.md` and are the same here.

Two things are its own. The home is remembered per list, so ⇧⌘F answers where the
last ⇧⌘F answered whatever Find Usages has been asked to do. And ⇧⌘F puts the
keyboard in the *query field* rather than in the rows — asking is typing a
question — where a move puts it in the rows, because a pane being moved already
has an answer in it.

The controls go on two rows when the pane is too narrow for one, which is what
the sidebar is: the query field above, the three options, the `✓`, the count and
the Place control below it. Nothing is dropped — a results list that cannot be
re-asked is not the same list somewhere else.

### Scenario: search under the project view

- **Given** search results in the panel with two matches marked done
- **When** **Under the Project View** is chosen
- **Then** the sidebar splits with the tree above and the results below, the same
  two are still marked done, and the query is still there to be edited

### Scenario: the two lists remember different homes

- **Given** a usages list that has been sent to a window
- **When** ⇧⌘F is pressed
- **Then** the search results appear in the panel, where the last search was

### Scenario: asking, and then moving

- **Given** ⇧⌘F has just been pressed
- **When** nothing else is done
- **Then** the keyboard is in the query field
- **And** when the list is then moved anywhere, the keyboard is in the rows
