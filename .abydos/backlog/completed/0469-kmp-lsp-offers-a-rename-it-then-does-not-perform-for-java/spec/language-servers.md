## ADDED Requirement: A server that declines after offering is named

The two gates in front of a rename — the server's capabilities, then
`prepareRename` — cannot catch a server that passes both and then answers the
rename itself with nothing. kmp-lsp 0.25.0 did exactly that for every Java
symbol: it said it renamed, agreed there was a `Greeting` at that position, and
answered the rename with `null`.

Nothing was renamed, and that much has to be said, because a name was typed and
accepted and the code did not change. **What is said names the server**, which
is the only thing that distinguishes this from a caret on a comma. By this point
the caret was not on a comma: the server itself picked the symbol out and gave
back its extent, so "the server found nothing to change" describes the one
possibility that has been ruled out. Which server declined is a fact about
something somebody chose in `.abydos/tools.json` and can choose differently.

It is said as information rather than as an error. Nothing changed and nothing
is broken — a server declining is not a server failing, and the two do not
deserve the same colour.

### Scenario: a server that advertises rename and then declines

- **Given** a running server that renames, which answered `prepareRename` with a
  range
- **When** a new name is typed and accepted, and the server answers with no edit
- **Then** it says nothing was renamed, and names the server that declined
- **And** it says it as information rather than as a failure
