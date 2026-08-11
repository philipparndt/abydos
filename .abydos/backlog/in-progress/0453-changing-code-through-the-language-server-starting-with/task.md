# 453. Changing code through the language server, starting with rename

Everything this app asks a language server is a question. Nothing it asks
changes a file.

The requests implemented today are `completion`, `definition`, `hover`,
`references`, `documentSymbol`, `publishDiagnostics`, the `didOpen`/`didChange`/
`didSave`/`didClose` lifecycle, and `workspace/symbol`, `configuration` and
`executeCommand`. **There is no `textDocument/rename`, no `prepareRename`, no
`codeAction`, and nothing anywhere that applies a `WorkspaceEdit`.** So renaming
a symbol means find-usages and then editing each site by hand, which is the
thing a language server exists to stop somebody doing.

Rename is the one to build first — it is the refactoring people reach for daily,
every server implements it, and it is the smallest thing that requires the whole
mechanism underneath.

## The mechanism is the item, not the rename

A rename comes back as a `WorkspaceEdit`, and applying one is where all the
difficulty is:

- **It touches files that are not open.** A rename across five hundred bundles
  edits documents nothing has a `TextDocument` for. Each has to be read, edited
  and written without going through the editor — and the ones that *are* open
  have to change through the rope, or the buffer and the disk disagree.
- **It is one undo.** A rename that touched forty files and is undone forty
  times is not an undo. 0442 built `FileUndo` for what the *tree* does to files;
  this is the editor's equivalent and should be one entry, not forty.
- **`documentChanges` or `changes`.** Servers answer with either, and the first
  can carry file creations, renames and deletions as well as text — which is how
  a Java rename moves `Foo.java` to `Bar.java`. That means a workspace edit can
  reach the file tree, and 0442's undo and this one meet there.
- **It can fail halfway.** Twenty files written and the twenty-first refused
  leaves a project that compiles nowhere. Whether to write atomically, or to
  undo what was done, or to stop and say precisely where — is the question this
  item has to answer before any of it is useful.

## What is already in place

**The container edge is ready and has never been used.** `spec/tool-images.md`
already requires that `file:` URIs are rewritten in both directions "for the ones
that are values and for the ones that are keys, so that a workspace edit's map
crosses" — written while the containers were built, for a message this app has
never sent. Whoever builds this gets that for free and should check it rather
than assume it, since nothing has ever exercised it.

**`FileUndo`** is the pattern for the undo, and `TextDocument`'s rope is what an
open document has to change through.

## Beyond rename, and deliberately not now

`codeAction` is the other half of what a server can do to code — quick fixes,
organise imports, extract method — and it is a larger surface: actions have to be
offered where the cursor is, resolved lazily, and some of them are commands
rather than edits. **This item is rename and the `WorkspaceEdit` machinery
underneath it.** If that lands well, code actions are mostly a menu on top of the
same mechanism — which is **0456**, filed and explicitly waiting on this one.

## Worth deciding

- **Where the new name is typed.** The navigator renames a file in place on the
  row, from 0439, and that machinery already handles refusal and the field
  staying open. A symbol rename in the editor is the same gesture one layer in,
  and reusing that idea rather than a dialog would match the app — Toast.swift's
  rule about not interrupting applies here too.
- **What to do when the server does not support it.** `prepareRename` and the
  server's own capabilities say so. An offer that fails is worse than an absence.
- **kmp-lsp implements rename**, and it is syntactic — so a rename it performs is
  a text substitution over what it indexed, not a type-aware one. If 0449 has
  pointed a project at it, the rename that arrives is a different promise from
  jdtls's, and somebody should be told which they are getting.

## Estimate

2026-08-11 13:12 — about two hours left

## Steps

Finer than the list this was filed with. Each of the four hard parts above is
more than one thing somebody can go and look at, and the mechanism turned out to
be worth separating from the gesture that sits on it — which is the item's own
sentence about itself, made into a checklist.

**The mechanism**

- [x] A `WorkspaceEdit` is read from both shapes, and text edits go into text
      correctly — backwards by position, characters counted in UTF-16, all three
      line endings
- [x] `WorkspaceEditPlan` works the whole edit out without touching anything,
      simulating `documentChanges` in order so that a file which moves is right
      whichever way round the server sends it
- [x] `WorkspaceEditApplier` carries a plan out, and puts back what it did when
      a write refuses partway
- [x] A partial failure says exactly what was written and what was not
- [x] The container edge is *driven* rather than assumed: a workspace edit's map
      of changes crosses by its keys

**The requests**

- [x] `prepareRename` and `textDocument/rename` on `LSPClient`, and the client
      capabilities that make a server answer with `documentChanges` at all
- [x] `prepareRename` and the server's capabilities decide whether rename is
      offered at all
- [x] Somebody is told when the rename on offer is a syntactic one (kmp-lsp)
      rather than a type-aware one (jdtls)

**The gesture**

- [ ] Where the new name is typed
- [ ] `textDocument/rename`, and a `WorkspaceEdit` applied to open documents
      through the rope and to closed ones on disk
- [ ] `documentChanges` as well as `changes`, including a file that moves
- [ ] One undo for the whole edit

**Evidence**

- [ ] Drive it across the corpus — a rename touching several bundles, and the
      same rename with the project in a container, which is the path that was
      built for this and never used
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
