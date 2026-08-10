# What backlog-spec does

One file per capability, each a list of requirements. This is the
account of the program that stays: the backlog says what to do and then
forgets, and once enough items are in `completed/` the only other
account of what the program does is the program itself.

A file looks like this:

    # Terminal

    One paragraph on what this part of the program is.

    ## Requirement: A pane keeps its ligatures when another is focused

    Prose saying what is true, in the present tense, about the program as
    it is now.

    ### Scenario: two panes, the second focused

    - **Given** two panes showing the same file
    - **When** the second is focused
    - **Then** the first still draws `!=` as one glyph

Nothing is edited here by hand while an item is in flight. A change to
behaviour is written as a delta inside the item that makes it —
`spec/<capability>.md` in the item's folder, with `ADDED`, `MODIFIED` or
`REMOVED` in front of each requirement — and folded in when the item is
finished, by `abydos-backlog done <number>`. That way the spec and the
code change in the same commit, and a requirement never arrives here
before the thing it describes.
