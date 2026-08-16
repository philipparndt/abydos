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

## REMOVED Requirement: Marking done is never a deletion, and never wears ⌫

⌫ now marks a result done, so the name is false where it is most load-bearing.
The requirement itself is not gone — it comes back under a name that says what
is true, with ⌘⌫ still unbound and its scenario word for word. A rename is a
REMOVED and an ADDED.

## ADDED Requirement: Marking done is never a deletion, and ⌘⌫ is never the key for it

One pane away, in the project tree, ⌘⌫ moves a file to the trash, and the two
panes are the same list-shaped thing full of file names. So the interface never
says "delete", "remove" or "dismiss" of a search result: the words are **Mark as
Done** and **Mark as Not Done**, and the status line counts what is `done`.

Two keys tick a row off, and neither of them is the destructive one. ␣ ticks a
checkbox everywhere in the system and destroys nothing anywhere. ⌫ is what takes
a result off the list in the editor a lot of these hands arrive from, and it is
safe to mean the same thing here because bare ⌫ moves nothing to the trash
anywhere in this program: the tree's key is ⌘⌫ and only ⌘⌫. Which is the other
half of this — **⌘⌫ is not bound in the results list and does nothing at all
there**: nothing is marked, nothing is unmarked, and no file is touched.

### Scenario: the key that trashes a file one pane over

- **Given** the keyboard in the search results, with a match selected
- **When** ⌘⌫ is pressed
- **Then** nothing is marked, nothing is unmarked, and no file is moved

### Scenario: the space bar

- **Given** the keyboard in the search results, with rows selected
- **When** ␣ is pressed
- **Then** they are marked done, and pressing it again marks them back

### Scenario: the delete key

- **Given** the keyboard in the search results, with rows selected
- **When** ⌫ is pressed
- **Then** they are marked done, and pressing it again marks them back, exactly
  as ␣ does
