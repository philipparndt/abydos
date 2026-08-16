<!-- What this item changes about `language-servers`. Folded into
     .abydos/backlog/spec/language-servers.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
-->

## ADDED Requirement: A completion is inserted as text, and its stops are stepped through

A server answers with more than a word. `insertText` may be written in the
snippet syntax — `insertTextFormat: 2` — where `$0` is where the caret ends up,
`${1:size}` is a default to type over and `${1|a,b|}` is a choice. **None of
that is text to paste.** Inserted as written it is a syntax error somebody has
to notice and delete, which is what taking `union` used to leave behind:
`union() $0`, dollar and all.

So a completion is expanded before it goes in: every stop leaves its default
text, escapes are honoured — `\$` is a dollar, which matters for shell
completions where eating one would rewrite the command — and the caret goes
where `$0` said.

**A completion with more than one place for the caret is stepped through.** The
first stop is *selected* rather than merely arrived at, so typing replaces it;
Tab moves to the next and ⇧Tab back; the last stop is `$0` however early it was
written. A stop the server numbered twice is one stop, at its first mention, and
the second stays as text — this does not mirror. A stop inside another stop's
default is left as text for the same reason: the two ranges would overlap, and
typing into the outer one would destroy the inner.

The stops follow the text they mark while it is typed into, and the session
lasts exactly that long. **An edit anywhere but the stop being typed into ends
it**, as does Escape, as does Tab off the last stop; after that Tab is the
indent key again. Nothing here guesses where a stop went: a range that cannot be
followed honestly is dropped rather than moved to a place it might not be.

A completion with a single place for the caret — `union() $0`, or a plain word —
is not a session. The caret goes where it said, and Tab means what Tab always
means.

### Scenario: taking a completion that names an argument

- **Given** a `.scad` and a server that answers `cube` with
  `cube(size = ${1:size}, center = false);$0`
- **When** the completion is taken
- **Then** the file says `cube(size = size, center = false);`
- **And** the `size` between the `=` and the comma is selected

### Scenario: typing over the first stop and moving to the last

- **Given** that completion just taken, with `size` selected
- **When** `10` is typed and Tab pressed
- **Then** the line reads `cube(size = 10, center = false);`
- **And** the caret is at the end of it, where `$0` was

### Scenario: a completion with nowhere to move to

- **Given** a server that answers `union` with `union() $0`
- **When** the completion is taken and Tab pressed
- **Then** the file says `union() ` with no dollar in it
- **And** the Tab indents, because there was never a second stop

### Scenario: editing away from the stops

- **Given** a completion taken and its first stop selected
- **When** something is typed at the other end of the line
- **Then** Tab indents rather than jumping into text that has moved
