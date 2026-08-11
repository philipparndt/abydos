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

## Estimate

2026-08-11 20:15 — about two hours left

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
- [ ] ⌘/ in the menu and the responder chain, over a caret and over a selection
- [ ] One undo for the whole toggle, through the rope, the way 0453 applies edits
- [ ] The selection still covers the same text afterwards
- [ ] Languages with no line comment: decided, and audible rather than silent
- [ ] Watch it on a real file of each shape — indented Swift, a Makefile where
      the indent is a tab, YAML, and something with no line comment
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
