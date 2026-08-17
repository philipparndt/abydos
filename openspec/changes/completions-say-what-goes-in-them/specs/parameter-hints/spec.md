## ADDED Requirements

### Requirement: The parameter being filled in is named while it is being filled in

The editor SHALL show what the parameter under the caret takes, for as long as a
snippet session is live or the caret is inside an argument list. A completion is
taken and its first stop is selected — `cube(size = size, center = false);` with
`size` highlighted — and that is the moment somebody needs to know what `size`
is. The list has closed by then.

It SHALL be one thing on screen whichever server answered, and it SHALL NOT be
drawn in the strip after the end of the line, which the inline diagnostic owns.

#### Scenario: the hint outlives the list

- **GIVEN** `cube` taken in a `.scad`, with `size` selected as the first stop
- **WHEN** the completion list has closed
- **THEN** what `size` takes is still on screen

#### Scenario: the hint follows Tab

- **GIVEN** that session with `size` selected
- **WHEN** `10` is typed and Tab moves to the next stop
- **THEN** the hint names that stop's parameter instead

#### Scenario: the hint goes when the session does

- **GIVEN** a live snippet session showing a hint
- **WHEN** Escape ends it, or an edit away from the stops ends it
- **THEN** the hint goes with it

### Requirement: Signature help is asked of servers that offer it

Where `initialize` returned a `signatureHelpProvider`, the editor SHALL send
`textDocument/signatureHelp` and SHALL use the reply for the hint: the signature
label, with the parameter the server marks `activeParameter` distinguished from
the rest using the offsets it sends. sourcekit-lsp answers with
`extruded(height: Double, topEdge: EdgeProfile) -> any Geometry3D`,
`activeParameter: 1`, and label ranges `[9, 23]` and `[25, 45]`.

Where a server returned no `signatureHelpProvider` — openscad-lsp returns none,
and does not answer the request at all — the editor SHALL NOT send the request.

#### Scenario: inside a Swift call

- **GIVEN** a warm `sourcekit-lsp` and the caret after `.extruded(height: height, `
- **WHEN** the hint is shown
- **THEN** it reads the whole signature
- **AND** `topEdge: EdgeProfile` is the part marked as the one being filled in

#### Scenario: a server that does not offer it

- **GIVEN** `openscad-lsp`, whose capabilities carry no `signatureHelpProvider`
- **WHEN** the caret is inside a call
- **THEN** no `textDocument/signatureHelp` request is sent
- **AND** the editor does not wait on a reply that never comes

### Requirement: Without signature help, the hint comes from the taken completion

For a server with no `signatureHelpProvider`, the hint SHALL come from the
documentation of the completion that was taken, kept for the life of the snippet
session, keyed by the active stop's own name — `${1:size}` names `size`, which is
what openscad-lsp's prose has a heading for.

The match SHALL be exact. Where the active stop's name is not found in the
documentation, nothing is shown: the wrong type under the caret is worse than no
type, because it will be believed.

#### Scenario: the stop names the parameter

- **GIVEN** `cube(size = ${1:size}, center = false);$0` taken, with `size` selected
- **WHEN** the hint is shown
- **THEN** it is the server's own description of `size`

#### Scenario: a stop the prose does not describe

- **GIVEN** a completion whose stop is named something the documentation never
  mentions
- **WHEN** that stop becomes active
- **THEN** no hint is shown for it, rather than a neighbouring parameter's
