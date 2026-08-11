# 469. kmp-lsp offers a rename it then does not perform for Java

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

## What it turned out to be

**A kmp-lsp bug, and a small one.** Not a limitation to state: the index was
never the problem. `find_definition_qualified` resolves a Java class, field and
method perfectly — which is why `references` answered 263 locations — and the
only thing standing between that and a rename was one node-kind check.

`classify_symbol_at` (`src/indexer/infer/cst_symbol.rs`) opens with

    if !matches!(node.kind(), KIND_SIMPLE_IDENT | KIND_TYPE_IDENT) { return None; }

**tree-sitter-java names declarations with `identifier`.** tree-sitter-kotlin
uses `simple_identifier`/`type_identifier`, and this whole file was written for
Kotlin. So the cursor's node was rejected before any of the declaration arms
ran, `classify_cursor` answered `None` for every position in every Java file,
and `rename_impl` turned that `None` into `Ok(None)`. Every deliberate refusal
below it — ambiguous identity, library symbol, override relationship — was
unreachable from Java, which is exactly why the answer carried no reason.

Nothing about the symbol, the position or the index. One `match` arm, in a file
whose module comment already says it is shared by five features.

## What changed, and where

`~/dev/kmp-lsp`, branch **`fix/java-rename`**, one commit **`8434ac3`** off
`main` (`9d6fbb6`). Not pushed. Two defects in the same request pair:

- **Java declarations classify.** `java_declaration_named_by` matches a Java
  declaration by its parent's `name:` *field* rather than by child position —
  `method_declaration` has `identifier`s in its `parameters:` subtree too, and
  only one of them is the method's own name. It tags each one `Indexed` or
  `LocallyScoped` according to what `extract_java` actually pushes into
  `f.symbols`, which is the same distinction `is_indexed_declaration_site`
  already draws for Kotlin.

- **`prepareRename` stops promising more than `rename` can keep.** It used to
  ask only whether the word under the cursor was longer than one character and
  not a keyword — a text scan, so it offered a rename for a word in a *comment*
  too, in Kotlin as much as in Java. Both requests now decide through one
  `rename_identity`: the local fast path, a single resolvable definition,
  nothing renameable at all, or a refusal with its reason. `prepareRename`
  answers `null` for the last two.

A Java **reference** is still left unclassified on purpose, and that is the
deliberate residue rather than an oversight: this grammar's member access is
`field_access`/`method_invocation`, which `CstQuery` cannot type, so classifying
one would say `Reference { receiver_type: None }` — and go-to-definition and
find-references, which share this classifier, would start believing that instead
of taking the string-first path Java has always taken. Renaming a Java class, a
field or a method works; renaming from a parameter, a local, a bare reference or
a member access does not, and is no longer offered.

### Measured, over the wire, on both binaries

A throwaway LSP driver, `initialize` → `didOpen` → `prepareRename` → `rename`,
against the two builds. Two Java files first, then the corpus as an APFS clone
of the five databinding bundles of `eclipse.platform.ui` (487 Java files), the
way 0453 does it. Load average 19–26 throughout — two other agents building —
and every answer came back in 0.1–0.2s, so nothing here is timing-sensitive.

|                                    | `main` (as filed)   | `fix/java-rename`     |
| ---------------------------------- | ------------------- | --------------------- |
| two files, class                   | `null`              | 2 files, 2 edits      |
| two files, method                  | `null`              | 2 files, 2 edits      |
| corpus, `ObservableTracker`        | `null`              | **62 files, 203 edits** |
| corpus, a private static field ×3  | `null`              | 1 file, 5 edits       |

The 203 edits are exactly the 203 locations `references` reports for the same
position, which is the right number for a server whose rename *is* a verified
reference search — and precisely what `isSyntactic` warns about before the name
is typed.

**Kotlin was never affected and is unchanged.** Driven the same way: a class, a
property, a method, a parameter and a local all renamed on `main` and rename
identically on the branch. The one difference is an improvement — a bare
property reference used to be offered and then refused with "identity is
ambiguous"; it is now not offered. So the guess in this item was right about
where the server's attention had been, but Kotlin needed no fix.

## What Abydos now says

`RenameAnswer` (`Sources/AbydosKit/LSP/RenameOffer.swift`), where the other
rename sentences live, so a test can read them without a window:

- before: **"Nothing was renamed" / "The server found nothing to change."**
- now: **"Nothing was renamed" / "kmp-lsp offered this rename and then found
  nothing to change."**

Information, not an error. `LanguageService.rename` carries the server's name out
with the answer rather than leaving the call site to look it up again — which
server was asked is decided in one place, by `ready`, and two answers to that
question can disagree.

## A surprise worth writing down

**This item says the `isSyntactic` warning "is written and tested and correct".
It was written and correct and *not tested*.** There was no
`RenameOfferTests.swift`, and nothing in `Tests/` mentioned `isSyntactic`,
`caveat`, `serverCannot`, `notHere`, `RenameSubject` or `RenameOffer` — the
commit that introduced them touched twelve files and no test. There is one now,
covering the caveat sentence, both silent refusals, the named one, and the new
answer. It is the sentence that goes in front of the Java rename this item
turned on, so it starts mattering today.

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
- **Kotlin having the same bug.** It does not, and never did: driven over the
  wire on `main`, a Kotlin class, property, method, parameter and local all
  rename. The server's rename tests being Kotlin turned out to be the reason
  Kotlin worked, not a hint that only Kotlin had been checked.
- **Making Java references classify too.** Tried and deliberately not kept.
  `classify_cursor` is shared with go-to-definition, goto-implementation,
  find-references and its per-candidate verification, and a Java reference can
  only ever classify as `Reference { receiver_type: None }` until `CstQuery` can
  type a `field_access`/`method_invocation` receiver. That is no better than the
  string-first path those features already take for Java, and it would silently
  redirect them. Java declarations are gated in; Java references are not.
- **A rename that bypasses the identity gates for Java.** The tempting shortcut
  — rename whatever `references` reports — would have skipped the ambiguous,
  library and override refusals the fork built on purpose. Not needed: the
  gates pass for a Java declaration once it classifies, and `ObservableTracker`
  in the corpus goes through all of them.
- **The two `lsp_smoke` failures being ours.** `smoke_completion_from_compiled_jar`
  and `smoke_reindex_command_picks_up_newly_configured_jar` fail identically on
  `main` at `9d6fbb6` — a fixture JAR whose `LazyLibType` never appears within
  30s. Checked out and run there to be sure.

## Estimate

2026-08-11 15:43 — done, finishing the commit

## Steps

- [x] Decide whether the fix is in kmp-lsp or in what it advertises
- [x] Fix `classify_symbol_at` so Java declarations classify at all
- [x] `prepareRename` answers `null` where `rename` would not produce an edit
- [x] Check whether Kotlin renames, since nothing here has driven it
- [x] Say which server declined, when one that advertised rename answers `null`
- [x] Test the `isSyntactic` caveat and the refusals 0453 left untested
- [x] Drive both server builds over two files and over the corpus
- [x] Write down here what was ruled out on the way
- [x] `spec/language-servers.md` says what the project now does
