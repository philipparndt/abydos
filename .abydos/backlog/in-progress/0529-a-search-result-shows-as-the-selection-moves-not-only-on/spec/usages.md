<!-- What this item changes about `usages`. Folded into
     .abydos/backlog/spec/usages.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       Usages arrive in the bottom panel, beside search
       A usages list is the same checklist search is
       ↓ through a usages list shows each one and keeps the keyboard
       A usages list can be expanded into a window, and that is remembered
       The keyboard stays in the list in every home, including beside a terminal
-->

## MODIFIED Requirement: A usages list is the same checklist search is

The usages list and the search results are one list with two different things
above it. Everything the search results do, the usages list does, and for the
same reasons: rows are selected several at a time and marked **done** with ␣ or
⌫, which strikes them through and leaves them where they are; a file heading
takes every usage in the file with it and counts how many of its own are done;
`✓` hides what is finished; ⌘Z in the list takes back the last marking and ⇧⌘Z
puts it back.

It runs the other way as well. **↓ shows the row it lands on in both lists**,
which was for a while the one thing the usages list did and the search results
did not — see `search.md`. There is no gesture left that means two different
things in the two of them.

⌫ is the key that takes a usage off the list in the editor a lot of these hands
arrive from, and it is one of the two here because it is the first thing they
press. It is safe to be: bare ⌫ moves nothing to the trash anywhere in this
program. **⌘⌫ is the one that does, one pane over, and it does nothing at all in
the usages list.** Marking is never a deletion whichever key does it, and the
words are **Mark as Done** and **Mark as Not Done**. A usage list is transient,
which is an argument for rows that vanish and is answered by `✓`: it gives the
shortening list without a gesture that reads as touching a file, and without
moving every row under the pointer on every press.

The ticks are kept per symbol — against the place the symbol was asked about —
so asking about a second symbol arrives unticked, and asking about the *same*
symbol again brings the ticks back with it. That last part is the normal thing to
do after fixing one of the usages.

### Scenario: ticking off two of a file's usages

- **Given** a usages list with three usages in `Theme.swift`
- **When** two of them are selected and ␣ is pressed
- **Then** both are struck through and the heading reads `2/3`

### Scenario: the same two with the other key

- **Given** the same list, nothing yet marked
- **When** the same two are selected and ⌫ is pressed
- **Then** both are struck through and the heading reads `2/3`, and pressing ⌫
  again brings them back

### Scenario: the key that trashes a file one pane over

- **Given** the keyboard in the usages list with a usage selected
- **When** ⌘⌫ is pressed
- **Then** nothing is marked, nothing is unmarked, and no file is moved

### Scenario: asking again about the same symbol

- **Given** twelve usages of a symbol marked done
- **When** Find Usages is asked about that same symbol again
- **Then** the new list comes back with those twelve still marked

### Scenario: asking about a different symbol

- **Given** the same twelve marked done
- **When** Find Usages is asked about another symbol
- **Then** nothing in the new list is marked

### Scenario: the same walk in both lists

- **Given** a usages list and a set of search results, each with the keyboard
  in it
- **When** ↓ is pressed in each
- **Then** both show the row it lands on, in the provisional tab, with the
  keyboard still in the list
