# 456. Code actions: what a server offers to do about the line you are on

The follow-up 0453 named and deliberately did not take. **Do not start this
before 0453 lands** — it is mostly a menu on top of that item's `WorkspaceEdit`
machinery, and building the menu first means building the machinery twice.

Quick fixes for a diagnostic, organise imports, extract method, add the missing
import, implement the protocol's requirements: `textDocument/codeAction` is how a
server offers all of them, and this app asks for none.

## Why it is a larger surface than rename, and not just more of it

Rename is one request with one answer. Code actions differ in four ways, and each
is a decision rather than a line of code:

- **They are offered rather than asked for.** A rename begins with somebody
  deciding to rename. A code action has to be *discovered* — something has to
  say "there are three things you could do here" without being asked, and
  without becoming noise on every line. Where that indicator lives, and whether
  it appears on the diagnostic, in the gutter, or only on a keystroke, is the
  main design question in this item.
- **They arrive lazily.** A server may return an action with no edit at all and
  fill it in only when `codeAction/resolve` is called, so the list is cheap and
  the work happens on the one somebody chose. Treating an unresolved action as
  empty is the obvious first bug.
- **Some are commands, not edits.** An action may carry a `command` rather than
  a `WorkspaceEdit`, which goes back through `workspace/executeCommand` — which
  this app already implements — and the server then *asks the client* to apply
  an edit via `workspace/applyEdit`. That is a request coming the other way, and
  nothing here handles inbound requests that change files.
- **They are scoped to a range and a context.** The diagnostics under the cursor
  are part of the request, so an action list depends on what the server most
  recently published, not only on where the caret is.

## What must exist first, from 0453

Applying a `WorkspaceEdit` — open documents through the rope, closed ones on
disk, one undo, `documentChanges` including file moves, and an honest answer when
it fails halfway. All of that is 0453's, and every code action ends in it.

## Worth deciding when it is started

- **Whether a quick fix for a diagnostic and a refactoring share one gesture.**
  They are the same protocol request with different `kind`s — `quickfix`,
  `refactor.extract`, `source.organizeImports` — and one menu holding all of
  them is what most editors do, but "fix this error" and "restructure this code"
  are different intentions and a single list mixes them.
- **`source.*` actions have no cursor.** Organise imports is about the file, not
  a position, so it belongs somewhere other than a menu that appears at the
  caret.
- **What kmp-lsp offers**, since 0449 lets a project choose it: it is syntactic,
  so its actions are text substitutions and its list will be shorter and
  different in kind from jdtls's. Somebody should be able to tell which they are
  getting rather than wondering why the menu changed.

## Steps

- [ ] 0453 first — the `WorkspaceEdit` machinery is the whole foundation
- [ ] `textDocument/codeAction`, scoped to the selection and carrying the
      diagnostics under it
- [ ] `codeAction/resolve` for actions that arrive without an edit
- [ ] `workspace/applyEdit` — an inbound request that changes files, which
      nothing here handles yet
- [ ] Somewhere to see that actions exist, without it becoming noise
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
