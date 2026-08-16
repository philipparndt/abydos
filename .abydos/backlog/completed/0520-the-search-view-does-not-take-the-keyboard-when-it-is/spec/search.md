<!-- What this item changes about `search`.

     The rule this item is judged by — ⇧⌘F puts the keyboard in the query
     field — was already here and already right. The program failed it in
     one of the four homes. So this is not a spec that described the wrong
     behaviour; it is a spec that said the rule once and then handed
     "where the keyboard ends up" wholesale to `usages.md`, which says the
     rows. That sentence is where the exception went missing, and closing
     it is the whole of the change: the field rule holds in **every** home,
     with a scenario in the home that broke.
-->

## MODIFIED Requirement: Search results go wherever a usages list goes

The search results are the same checklist the usages list is, so they have the
same four homes and the same **Place** control to choose between them: a tab in
the bottom panel's strip, the lower half of the sidebar under the project view, a
column of the panel beside the terminals, or a window of its own. What each of
them is, what survives a move, and which of them hold one list are all said in
`usages.md` and are the same here.

Two things are its own. The home is remembered per list, so ⇧⌘F answers where the
last ⇧⌘F answered whatever Find Usages has been asked to do. And ⇧⌘F puts the
keyboard in the *query field* rather than in the rows — asking is typing a
question — where a move puts it in the rows, because a pane being moved already
has an answer in it.

**The field rule holds in every one of the four homes, and on every ⇧⌘F rather
than only the first.** This is the one place where search and usages want
opposite things: `usages.md` says a list arrives with the keyboard in its rows,
and beside a terminal it says so emphatically, because a shell takes every
keystroke it is given. A search being *asked for* is the exception to that, in
the panel, under the project view, beside the terminals and in a window alike —
otherwise the second ⇧⌘F of a session lands in the results of the first, the
caret blinks in a field nothing typed reaches, and the way to ask a new question
is to click.

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

### Scenario: asking again, at a list beside the terminals

- **Given** search results beside the terminals, left for the editor with ⇥
- **When** ⇧⌘F is pressed
- **Then** the keyboard is in the query field with the old query selected, and
  what is typed replaces it rather than reaching the rows
