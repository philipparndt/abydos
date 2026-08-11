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

## What was decided, and what was found

### Failing halfway: three layers, and the first one does the work

Not "write atomically" — there is no atomic multi-file write on this operating
system and pretending otherwise would have been a lie in a comment. Not "undo
what was done" on its own either, because a rollback is a second thing that can
fail. The answer is:

1. **Everything is read, edited and checked while nothing has been written.**
   `WorkspaceEditPlan` is a pure function of the edit and the text. Almost every
   reason an edit fails is knowable there — a file that is not there, a range
   the file does not have, two edits over one character, a rename onto a name
   something holds — and **one refusal means nothing happens at all**.
2. **A write that fails anyway is put back**, from the previous contents the
   plan already carries. That is the same information ⌘Z needs, so the rollback
   and the undo are literally the same walk over the same data. Two mechanisms
   here would be two that come to disagree.
3. **A rollback that cannot finish names every file on both sides.** It takes
   the file system refusing twice, and when it happens being exact is all that
   is left.

`WorkspaceEditPlanTests` drives all three, including twenty files with the
fifteenth read-only, and the floor where the write refuses *and* the putting
back refuses.

### Where the name is typed

A field over the symbol, in the text, scrolling with it — the navigator's
in-place rename one layer in, as the item guessed. A subview of `CodeView` and
not a child panel: the completion list is a panel because it must hang past the
editor's edges and must never take focus, and this is the opposite of both.

`RenameField` is the navigator's pattern *extracted* rather than copied a fourth
time — there were already three near-identical copies (the navigator row, the
terminal tab strip, the changes pane), each with its own version of the same
four rules. The two that are easy to get wrong and cost somebody a day: never
`makeFirstResponder` on the field that already has it, and clear the field
before removing it from its superview.

### When the server will not do it

Two gates, in order, and only one of the three refusals is said out loud. This
is the first thing in the whole app to read `LSPClient.capabilities` — nothing
had ever gated on them.

`prepareRename` is asked **only of servers that advertise it**, which was not
obvious: several servers rename and answer `MethodNotFound` to that question,
and a refusal is indistinguishable from "nothing here". For those the word under
the caret is what the field opens on.

## What was found on the way

**The container edge held.** `spec/tool-images.md` has required since the
containers were built that URIs cross for map keys as well as values "so that a
workspace edit's map crosses" — written for a message this program had never
sent. It is correct: a `changes` map keyed by `file:///workspace/…` comes home
keyed by this machine's paths, and a rename really does cross both ways against
a containerised gopls under Apple `container`. Driven now, in
`ContainerPathTests` and in `RenameLiveTests`, and in the app.

**jdtls sends both shapes, and the old one is empty.** Renaming
`ObservableTracker` over five of `eclipse.platform.ui`'s bundles, jdtls answered
with a `changes` map of **zero** files and a `documentChanges` list of **32**,
plus the file move. So a client that read `changes` — which is what a client
that claims nothing in its capabilities is sent — applies nothing at all and
reports success. That is the strongest argument there is for both the
`documentChanges`-wins rule and for growing `LSPClient.clientCapabilities`, and
it was measured rather than reasoned about.

**kmp-lsp advertises rename, prepares it, and then answers `null`.** Version
0.25.0 says `renameProvider: {prepareProvider: true}`; `prepareRename` answers
with a real range and placeholder; `textDocument/rename` answers `null` — for a
class, for a method, and for a private field, on the corpus and on a two-file
toy Java project. Its `rename_impl` returns `Ok(None)` when `classify_cursor`
cannot classify the cursor from the parse tree, and for Java it apparently
cannot. Its own refusals (ambiguous identity, library symbol, an override
relationship) come back as *errors* with reasons; this is not one of those.

So the syntactic caveat this item built is written, tested and correct, and the
server it was built for does not currently deliver a Java rename to put it in
front of. **This is exactly the failure the item named — an offer that fails —
arriving from the server rather than from the app**, and it is a case the two
gates cannot catch, because the server says yes twice and then does nothing.
The app's answer is honest but thin: "The server found nothing to change."
Worth filing on its own.

**jdtls without a target platform scopes a rename to one bundle.**
`ObservableTracker` is used in 62 files across the five databinding bundles;
jdtls renamed 32, all inside its own bundle. The five import as five Eclipse
projects with no inter-bundle classpath, because a PDE workspace resolves
dependencies through a target platform that nothing here provides. Not a defect
in this item — the mechanism carried every file the server named — but it is why
the corpus evidence is "32 files and a file that moved" rather than "six
bundles".

## Ruled out

- **Writing atomically.** No such thing across files. A staging directory and a
  final flurry of moves narrows the window and does not close it, and it doubles
  the number of file operations that can fail. Checking first and reversing
  second is smaller and covers more.
- **A dialog for the new name.** See above; and `Toast.swift`'s rule about not
  interrupting is the same rule.
- **Each `TextEdit` applied to an open document as its own `replace`.**
  `TextDocument` records an undo node per `replace`, so a file with forty edits
  in it would take forty presses of ⌘Z *inside that file* on top of everything
  else. One replacement of the whole text is one node, and the caret, the folds
  and the scroll position are put back the way `reloadFromDisk` puts them back.
- **Putting the undo on the document's own `UndoTree`.** It cannot hold this: a
  document's history knows nothing of the other thirty-nine, and a rename that
  moved `Foo.java` to `Bar.java` is not a text edit at all. It goes on the tree's
  stack, which already holds the gestures that act on files rather than on text.
- **Retargeting an open tab when its file moves.** `Tab.url` is a `let` and
  everything hanging off it — the language server's document, the breakpoints,
  the session — is keyed by that path. The tab is closed before the move and
  reopened after it, which loses the caret and is honest about it.
- **Trusting `changes` when a server sends both.** Measured above: it is empty.
- **Renaming in the corpus itself.** Every corpus run is over an APFS clone made
  by the test and thrown away. `Scripts/corpus.sh` puts somebody's checkout
  there, and a test that renamed thirty files in it would break every other test
  that reads it.

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

- [x] Where the new name is typed
- [x] `textDocument/rename`, and a `WorkspaceEdit` applied to open documents
      through the rope and to closed ones on disk
- [x] `documentChanges` as well as `changes`, including a file that moves
- [x] One undo for the whole edit

**Evidence**

- [x] Drive it across the corpus — a rename touching several bundles, and the
      same rename with the project in a container, which is the path that was
      built for this and never used
- [x] Write down here what was ruled out on the way
- [x] `spec/language-servers.md` says what the project now does — and
      `spec/tool-images.md`, whose container requirement this is the first thing
      to exercise
