## Context

Rename is one request with one answer, and it is what this app has. Code actions
differ in four ways, and each is a decision rather than a line of code.

**They are offered rather than asked for.** A rename begins with somebody
deciding to rename. An action has to be discovered — something says "there are
three things you could do here" without being asked, and without becoming noise.

**They arrive lazily.** A server may return an action with no edit and fill it in
only when `codeAction/resolve` is called, so the list is cheap and the work
happens on the one somebody chose.

**Some are commands.** An action may carry a `command` instead of a
`WorkspaceEdit`, which goes back through `workspace/executeCommand` — already
implemented here — and the server then asks the client to apply an edit through
`workspace/applyEdit`. Nothing in this app handles an inbound request that
changes files.

**They are scoped to a range and a context.** The diagnostics under the cursor
are part of the request, so the list depends on what the server last published.

What exists to build on is all of 0453: applying a `WorkspaceEdit` to open
documents through the rope and to closed ones on disk, as one undo, with file
moves, and a refusal that says what happened when part of it cannot be applied.

## Goals / Non-Goals

**Goals:**

- What a server offers about the line somebody is on can be seen and taken.
- An action that resolves lazily is resolved before it is applied.
- An action that is a command works, including the edit the server sends back.

**Non-Goals:**

- A second way to apply a `WorkspaceEdit`. 0453's is the one.
- Inventing actions this app thinks up itself.
- Deciding for the server which of its actions are worth showing.

## Decisions

**Where the offer lives is the item's main question and is left open here.** It
could be on the diagnostic, in the gutter, or only on a keystroke, and the
argument turns on how much of the time there is anything to offer — which nobody
has measured against jdtls, sourcekit-lsp and kmp-lsp. The work measures it
before choosing; a mark on every line is the outcome to avoid.

**Unresolved means unresolved.** An action with no edit is resolved on the way to
being applied, never treated as an empty edit. This is stated as a scenario
because the failure is silent: the menu works, the action does nothing.

**`workspace/applyEdit` is a request, not a notification.** It arrives from the
server, it changes files, and it expects an answer saying whether the edit was
applied. This is the first of its kind here, and answering it honestly — false
when the edit could not be applied — matters more than the happy path.

**One menu or two is deliberately undecided.** Quick fixes and refactorings are
the same request with different `kind`s — `quickfix`, `refactor.extract`,
`source.organizeImports` — and most editors put them in one list, but "fix this
error" and "restructure this code" are different intentions. Whichever is chosen,
`source.*` actions have no cursor: organise imports is about the file, so it does
not belong in a menu that appears at the caret.

**Which server is answering is worth being visible.** 0449 lets a project choose,
and kmp-lsp is syntactic — its actions are text substitutions, its list shorter
and different in kind from jdtls's. Somebody should be able to tell which they
are getting rather than wondering why the menu changed.

## Risks / Trade-offs

- **An indicator that appears constantly** is an indicator nobody sees. → Measure
  first; prefer a keystroke that always works over a mark that is always there.
- **An inbound request that writes files** is a new kind of trust. → It goes
  through 0453's applying, which already refuses what it cannot do and says so.
- **A slow server makes the menu feel broken.** → The list is one request; the
  resolve is one more, on the chosen action.

## Open Questions

- **One list or two**, and where `source.*` lives if it is not at the caret.
- **What a failed `applyEdit` should look like** to somebody who pressed a menu
  item and got a refusal from a program they did not know was involved.
- **Whether a quick fix should be reachable from the diagnostic's own sentence**,
  which is the place somebody is already looking when they want one.
