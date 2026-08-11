# 464. kmp-lsp offers a rename it then does not perform for Java

Found while building 0453, which is where rename came from.

**kmp-lsp 0.25.0 says it renames, agrees there is something to rename, and then
does nothing.** Three answers in a row, all from the same server about the same
symbol:

    initialize   → renameProvider: { "prepareProvider": true }
    prepareRename→ { "placeholder": "Greeting",
                     "range": { start: 0:13, end: 0:21 } }
    rename       → null

Reproduced on a two-file Java project of nine lines, and on
`eclipse.platform.ui` out of the corpus. It is not about the symbol: a class, a
method and a private static field all answer the same way. `references` on the
same position answers 263 locations, so the index is live and the position is
right.

`src/features/rename.rs` returns `Ok(None)` when `classify_cursor` cannot
classify the cursor's symbol from the parse tree, and for Java it apparently
cannot. Its *deliberate* refusals — an ambiguous identity, a library symbol, a
symbol in an override relationship — all come back as errors carrying a reason,
and this is none of those. Kotlin has not been checked.

## Why it matters here rather than upstream

0453's whole shape is that **an offer that fails is worse than an absence**, and
it built two gates for exactly that: the server's capabilities, and
`prepareRename`. This server passes both and then declines, which is the one
shape those gates cannot catch — and it is the server 0449 exists to let a
project choose, so somebody who has chosen it gets a field, types a name,
presses Return, and is told "The server found nothing to change."

0453 also built the sentence that warns somebody a rename from this server
matches names rather than types (`LanguageServerDefinition.isSyntactic`). That
is written and tested and correct, and there is currently no Java rename from
this server to put it in front of. It costs nothing to keep and starts working
the day this does.

## Worth deciding

- Whether this is a kmp-lsp bug to fix in `~/dev/kmp-lsp` — it is this project's
  own fork, from 0450 — or a limitation to state. If it is a limitation, the
  honest thing is for the server to answer `prepareRename` with `null` for
  symbols it will not rename, so that 0453's second gate closes.
- Whether Abydos should say more than it does when a server that advertised
  rename answers `null`. Today that reads "The server found nothing to change",
  which is what a caret on a comma also means. It could name the server, which
  is the one thing that distinguishes the two.
- Whether Kotlin is affected. Nothing here has driven kmp-lsp's Kotlin, and the
  server's own regression tests for rename are Kotlin.

## Ruled out

- **The index not being ready.** `references` at the same position, in the same
  session, answers 263 locations.
- **The position being wrong.** `prepareRename` at that exact position answers
  with the correct range and placeholder.
- **The symbol being unusual.** A public class, a static method and a private
  field all behave the same.
- **A capability this client fails to advertise.** The probe that reproduces it
  sends `workspace.workspaceEdit.documentChanges` and all three resource
  operations, which is what makes jdtls answer with a full edit for the same
  kind of symbol.

## Steps

- [ ] Decide whether the fix is in kmp-lsp or in what it advertises
- [ ] If it stays, `prepareRename` answers `null` where `rename` will
- [ ] Check whether Kotlin renames, since nothing here has driven it
- [ ] Say which server declined, when one that advertised rename answers `null`
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
