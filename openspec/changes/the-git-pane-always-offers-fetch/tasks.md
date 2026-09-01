## 1. The control

- [ ] 1.1 Replace the repository row's symbol `secondaryAction` with a titled one reading `Fetch`, drawn with the library from `the-zoom-reaches-every-control`.
- [ ] 1.2 Draw no secondary control where the repository has no remote, and drop the no-remote branch from `refreshPressed()`.
- [ ] 1.3 Put the local re-read on the row's context menu beside the verbs already there.
- [ ] 1.4 Rename `pressRefreshGlyphForTesting` for what it presses now, and keep the driver step working.

## 2. Proving it

- [ ] 2.1 Driven on a scratch repository one commit ahead: the row's verb reads `Push` and a `Fetch` control is on the row beside it.
- [ ] 2.2 Driven with no remote: no secondary control, and the re-read is on the menu.

## 3. Finishing

- [ ] 3.1 Say the removal in the release notes: the glyph is gone and what took its place.
- [ ] 3.2 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the delta in this change is what
it makes true.
