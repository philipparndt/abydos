# 475. Comment and uncomment the lines somebody has selected

> the next important feature for the editor is commenting / uncommenting (toggle
> line comments through "cmd + /"

⌘/ over a caret comments its line; over a selection, the lines the selection
touches; pressed again, it takes the comment off. One undo for the whole thing.

`⌘/` is free — nothing in the app binds `"/"` as a key equivalent.

## Where the comment tokens have to live, which is the one structural decision

`LanguageDefinition` (`Sources/AbydosKit/Syntax/LanguageRegistry.swift:34`) holds
an id, a display name, a parser, a bundle name, a `LanguageConfiguration` and a
fold query. **It has no comment token and it is the wrong place for one**, for a
reason that matters: a definition exists only where there is a *grammar*, and this
feature is wanted for every file somebody opens. There are 25 registered grammars;
`extensionMap` resolves far more ids than that, and a `.go` file whose grammar
failed to load still wants ⌘/.

And tree-sitter cannot answer this even where it is available. A grammar's
`highlights.scm` says where a comment *is*; nothing in it says what to *write*. So
a table is unavoidable — the only question is what it is keyed on, and the answer
should be the same id space `languageId(for:)` and `languageId(forFenceInfo:)`
already produce, so that one file resolves to one answer everywhere.

**Put the rule in `AbydosKit` as a value, not in the view.** Text in, line range
in, syntax in, edits out — that is what the suite can reach, and the editor's job
is to apply them. 0453 built exactly this shape for `WorkspaceEdit` and it is the
pattern to follow, including its one-undo-per-edit.

## What has to be decided, because each of these is a way to get it subtly wrong

- **Toggle on what.** If every non-blank line in the range is already commented,
  uncomment; otherwise comment all of them. Any other rule fails to round-trip:
  "toggle each line independently" turns a half-commented block into its inverse,
  which nobody wants twice.
- **Which column.** At the shallowest indent common to the range, not column 0 —
  otherwise commenting an indented block destroys the shape of the code somebody
  is reading. Xcode and VS Code both do this and it is what makes the second press
  able to find the token again.
- **Blank lines.** Not commented (a `//` on an empty line is trailing rubbish),
  and they must not count against "is everything commented?" — one empty line in
  the middle of a commented block must not flip the toggle to *comment again*.
- **What uncommenting removes.** Exactly what commenting inserts, including the
  single space after the token if it is there and not if it is not. A file whose
  author wrote `//code` must not come back as ` code`.
- **Languages with no line comment at all.** CSS and JSON are the two here. CSS
  has only `/* */`; JSON has none. Decide per language and say so: wrapping the
  whole selection in one block comment does not toggle line-wise, and nested
  `/* */` is invalid, so an honest refusal may be better than a mangling. **A
  keystroke that silently does nothing is the worst of the three**, so if it
  refuses it should say why once.
- **Where the selection ends up.** Over the same text afterwards, or the second
  ⌘/ acts on something else. A caret with no selection should stay on its line and
  keep its column as nearly as the inserted token allows.

## Deliberately out of scope, and say so in the item

- **Block-comment toggling as a separate gesture** (⌥⌘/ elsewhere). This item is
  line comments.
- **Injected languages.** A `<script>` in HTML and a fenced block in Markdown
  really do want the inner language's token, and `languageId(forFenceInfo:)`
  exists — but the range-to-language mapping does not, and building it here would
  make a small item large. Note what happens today at the boundary rather than
  pretending.

## What it turned out to be — read this before changing any of it

Three files: `Syntax/CommentSyntax.swift` is the table, `Text/LineComment.swift`
is the toggle, and `Rope.lineSpan(touchingUTF16:)` is which lines a selection
touches. `CodeView.toggleLineComment()` is the only part in the view, and it does
two things nothing else can: one `document.replace` over the whole block, and the
selection arithmetic afterwards.

**There are five languages with no line comment, not two.** The item said CSS and
JSON; HTML — and the XML this editor shows through HTML's grammar — plus Markdown,
`markdown_inline` and Svelte are in exactly the same position, and finding that
out was most of the work of deciding the table. Twenty-eight ids in all:
`LanguageRegistry.allLanguageIds` is new so that number is *checked* and not
counted by hand, and `everyLanguageIdHasAnAnswer` fails if an extension is added
without deciding what ⌘/ does in it.

**On a German keyboard the menu shows ⌘ß.** AppKit localises key equivalents
automatically (`allowsAutomaticKeyEquivalentLocalization`, on by default), and
`/` on that layout needs Shift, so it moves the shortcut to a key that does not.
`--comment-key` prints `key=ß`, which looked like a bug for a minute and is the
feature doing its job: the alternative is ⌘⇧7. It is left alone.

**The Makefile found the last bug.** With the token at column zero, both ends of a
whole-line selection sit exactly where it is inserted, and they want opposite
answers — carried along is right for a caret and wrong for the start of a
selection, which came back with the first two characters of its first line no
longer highlighted. Hence `Toggle.offset(_:isStartOfSelection:)`.

### Ruled out

- **Hanging the token off `LanguageDefinition`.** The item's own argument, and it
  held up: `plantuml` has no grammar and wants `'`.
- **Per-line block comments for CSS, HTML and Markdown** — `/* code */` on each
  line. It round-trips *most* of the time, and fails on a line that already
  contains one, because neither `/* */` nor `<!-- -->` nests. Most of the time is
  not a property an editing command may have, and the refusal is said out loud so
  it is not the silent third option. A separate ⌥⌘/ gesture is the honest home
  for this and is still out of scope.
- **Letting `jsonc` and `json5` have `//`.** They collapse onto the `json` id, and
  so does every `package.json`. Breaking a manifest on one keystroke is worse than
  refusing.
- **Commenting a lone blank line**, which VS Code does. The same code path would
  then put `//` and trailing whitespace on every line of an all-blank selection,
  and the rule that a `//` on an empty line is rubbish is the one the item is
  explicit about. So an all-blank range is `.nothing`.
- **Special-casing `///`.** `//code` has to count as commented — the item requires
  it — and by the same rule `/// doc` does too, so it uncomments to `/ doc`. Xcode
  and VS Code both do this; the alternative is the table knowing every language's
  doc-comment forms. `aDocCommentIsTreatedAsACommentTheWayEveryEditorDoes` is the
  test, named so nobody mistakes it for an oversight.
- **The smallest visual indent** as the column, instead of the longest common
  whitespace *prefix*. A width names a column that can fall inside a tab on one
  line and between two spaces on another; a prefix is a position every line has.
- **Widening the selection to whole lines**, the way ⇥ does. Right for indenting,
  wrong here: the second press would answer a different range than the first.
- **Pressing the key for real in a driver.** Tried, and it cannot work: a menu key
  equivalent is matched against the *key window's* responder chain, and a binary
  launched from a terminal is never key — activation is a request the window server
  does not grant it, and it must not, because stealing focus from whoever is
  working is worse than not being tested. A synthesised ⌘/ came back unhandled
  with no key window, indistinguishable from a shortcut that is not there; the
  command palette is blank in the same launch for every item in the menu, which is
  how that was diagnosed. `--comment-key` checks the three things that can
  actually be wrong instead: the item and its key, command-only modifiers, and
  that walking up from the first responder reaches something answering to the
  action. It reports `CodeView → … → MainWindowController`.

### What the injected-language boundary does today

Nothing clever, and it says so. ⌘/ asks the *file's* language and no more, so
inside a ```` ```swift ```` fence in Markdown it refuses — "Markdown has no line
comment" — and inside a `<script>` in HTML it refuses as HTML. Both were watched
doing it. Svelte refuses for the same reason rather than answering `//` for a file
that is markup at the top level. Which language a *range* is in has no answer in
this editor; only which language a file is in does, and building the first is the
item this one is deliberately not.

### Watched on a real file of each shape

Copies in a throwaway project, never anybody's own checkout — and worth knowing:
**the app saves on quit**, so the second run of a two-press check started from an
already-commented file until each run was given a fresh copy.

- **Indented Swift** (a copy of `LineIndent.swift`, lines 16–20, signature at one
  tab and body at two): `\t// ` on every line at the shared one-tab indent, the
  selection still over the same five lines, and `git diff --quiet` after the
  second press — byte for byte what it was.
- **A Makefile** (`build:` at column zero, its recipe behind a tab): `# ` at
  column zero on both, the recipe's tab still after it, round-trip identical. A
  caret alone at column 2 of the recipe line put the `#` after the tab and came
  back at column 4.
- **YAML** (a compose file, `image:`/`ports:`/`- 8080:80` at four and six spaces
  with a blank line in the middle): `#` at the four-space shared indent, the
  nesting kept, the blank line still blank, round-trip identical.
- **CSS and `package.json`**: both untouched, both with a toast — "Nothing was
  commented out: CSS has no line comment — only /* … */, which cannot be nested."

## Estimate

2026-08-11 21:20 — about ten minutes left

## Steps

- [x] Comment syntax as a value in `AbydosKit`, keyed on the same ids
      `languageId(for:)` produces, covering every id in `extensionMap` and not
      only the languages with grammars
- [x] `LanguageRegistry.allLanguageIds`, so that table can be *checked* rather
      than believed. Added because "covers every id" is not a claim anybody can
      make by reading a dictionary, and a new extension is the way it goes stale
- [x] The toggle as a pure function: text, line range and syntax in, edits out
- [x] One answer to "which lines does this selection touch", on the rope rather
      than privately inside the code view. Added because ⌘/ needs the rule ⇥
      already had, and two copies of it are two things that can drift
- [x] ⌘/ in the menu and the responder chain, over a caret and over a selection
- [x] One undo for the whole toggle, through the rope, the way 0453 applies edits
- [x] The selection still covers the same text afterwards
- [x] Languages with no line comment: decided, and audible rather than silent
- [x] A driver for each of those, since none of it is reachable from the suite:
      `--comment`, and `--comment-key` for the wiring the suite cannot see
- [x] Watch it on a real file of each shape — indented Swift, a Makefile where
      the indent is a tab, YAML, and something with no line comment
- [x] Write down here what was ruled out on the way
- [x] `spec/editor.md` says what the project now does. A new capability: nothing
      in `spec/` said anything about the editor itself before this
