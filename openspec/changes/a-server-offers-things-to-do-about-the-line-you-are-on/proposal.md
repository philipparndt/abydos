## Why

Quick fixes for a diagnostic, organise imports, extract method, add the missing
import, implement the protocol's requirements: `textDocument/codeAction` is how
a server offers all of them, and this app asks for none.

0453 built the half that every one of them ends in — applying a `WorkspaceEdit`
through the rope for open documents and on disk for closed ones, one undo,
`documentChanges` including file moves, and an honest answer when it fails
halfway — and named this as the follow-up it deliberately did not take. That item
is completed, so the machinery is there and the menu on top of it is what is
missing.

## What Changes

- **The editor asks for code actions**, scoped to the selection and carrying the
  diagnostics under it, because a server's answer depends on what it most
  recently published and not only on where the caret is.
- **An action that arrives without an edit is resolved before it is applied.**
  A server may return a list cheaply and fill in the work on
  `codeAction/resolve` for the one somebody chose. Treating an unresolved action
  as empty is the obvious first bug and is worth naming as a scenario.
- **An action may be a command rather than an edit.** That goes back through
  `workspace/executeCommand`, which this app already implements — and the server
  then asks the *client* to apply an edit through `workspace/applyEdit`. **That
  is an inbound request that changes files, and nothing here handles one.**
- **Somewhere to see that actions exist**, without becoming noise on every line.
  This is the main design question: an action is *offered* rather than asked
  for, so something has to say "there are three things you could do here"
  without being asked.
- **Not proposed: doing this before 0453's machinery existed.** It did not, and
  building the menu first would have built the machinery twice.
- **Not proposed: editing what a server sends.** Whatever it offers is what is
  shown, in its own words, the way rename already works.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `language-servers`: the capability says a server can change the code and that
  rename is what it is asked for. What a server *offers* to do — and what
  happens when the offer is a command, or arrives empty, or comes back as a
  request in the other direction — is the same subject and is not in it.

## Impact

- `Sources/AbydosKit/LSP/` — `codeAction`, `codeAction/resolve`, and the first
  inbound request that changes files: `workspace/applyEdit`.
- `Sources/AbydosApp/Editor/` — where an offer is shown, and the menu.
- Whatever 0453 left behind for applying a `WorkspaceEdit`, unchanged and reused.
- `.abydos/backlog/spec/language-servers.md`.
- From `.abydos/backlog` item 0456.
