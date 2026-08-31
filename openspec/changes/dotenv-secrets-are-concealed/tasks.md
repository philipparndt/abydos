## 1. What conceals, and where (AbydosKit)

- [ ] 1.1 `DotenvSecrets.conceals(fileNamed:)` for the name shapes `.env`, `.env.*`, `*.env`, and `*.dec`
- [ ] 1.2 `DotenvSecrets.valueRange(inLine:)` — after the first separator (`=`, and `:` in a `.dec` file's YAML shape), `export ` skipped, quotes covered whole, nil for comments, blanks and separator-less lines
- [ ] 1.3 `GitChangedLinesTests`-style fixture tests in `DotenvSecretsTests`: the name shapes in and out (`.env`, `.env.local`, `production.env`, `secrets.yaml.dec` in; `environment.swift`, `decode.swift` out), a plain value, a quoted value, an exported one, a comment, an empty value, a value containing `=`

## 2. The cover (CodeView)

- [ ] 2.1 `CodeView` learns it is showing a dotenv file (set at open from the kit's answer) and computes each visible row's cover rect from the line text via the existing range-to-rect machinery
- [ ] 2.2 The cover drawn after `drawLine` and before the caret — the paint order the editor delta states — opaque, rounded, minimum width, width stepped so length leaks only coarsely
- [ ] 2.3 Reveal state: a click on a cover reveals that value while the caret stays on its line; a per-view Reveal Secrets flag reveals the file; both explicit, nothing on caret arrival
- [ ] 2.4 View ▸ Reveal Secrets menu item with its state tick, enabled only for a dotenv tab

## 3. Proving it

- [ ] 3.1 A driven screenshot of an opened `.env`: keys readable, values as pills; a second after the file-wide reveal showing the values
- [ ] 3.2 A driver step reporting the covered/revealed state per line, so the arrow-walk-reveals-nothing and click-reveals-one claims are text a run can assert

## 4. Before finishing

- [ ] 4.1 `make test` clean, `make warnings` clean, machine load said if a bound flakes
- [ ] 4.2 No `.abydos/backlog/spec/*.md` file is made untrue: concealment is new; the editor's paint-order requirement is quoted whole in the delta with the cover's place added
