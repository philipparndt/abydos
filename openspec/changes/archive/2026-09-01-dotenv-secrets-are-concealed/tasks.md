## 1. What conceals, and where (AbydosKit)

- [x] 1.1 `DotenvSecrets.conceals(fileNamed:)` for the name shapes `.env`, `.env.*`, `*.env`, and `*.dec`
- [x] 1.2 `DotenvSecrets.valueRange(inLine:)` — after the first separator (`=`, and `:` in a `.dec` file's YAML shape), `export ` skipped, quotes covered whole, nil for comments, blanks and separator-less lines
- [x] 1.3 `GitChangedLinesTests`-style fixture tests in `DotenvSecretsTests`: the name shapes in and out (`.env`, `.env.local`, `production.env`, `secrets.yaml.dec` in; `environment.swift`, `decode.swift` out), a plain value, a quoted value, an exported one, a comment, an empty value, a value containing `=`

## 2. The cover (CodeView)

- [x] 2.1 `CodeView` learns it is showing a dotenv file (set at open from the kit's answer) and computes each visible row's cover rect from the line text via the existing range-to-rect machinery
- [x] 2.2 The cover drawn after `drawLine` and before the caret — the paint order the editor delta states — opaque, rounded, minimum width, width stepped so length leaks only coarsely
- [x] 2.3 Reveal state: a click on a cover reveals that value while the caret stays on its line; a per-view Reveal Secrets flag reveals the file; both explicit, nothing on caret arrival
- [x] 2.4 View ▸ Reveal Secrets menu item with its state tick, enabled only for a dotenv tab

## 3. Proving it

- [x] 3.1 A driven screenshot of an opened `.env`: keys readable, values as pills; a second after the file-wide reveal showing the values
- [x] 3.2 A driver step reporting the covered/revealed state per line, so the arrow-walk-reveals-nothing and click-reveals-one claims are text a run can assert

## 4. Before finishing

- [x] 4.1 `make test` green first try (3949 tests, 2 known issues) at load 12.4; `make warnings` clean; the four grown files re-recorded in the size ledger
- [x] 4.2 No `.abydos/backlog/spec/*.md` file is made untrue: concealment is new; the editor's paint-order requirement is quoted whole in the delta with the cover's place added

## 5. Refinements from review

- [x] 5.1 The cover is one fixed width for every value — the stepped width still said the secret's length; the value is erased to the row's edge in the row's own background and the pill is twelve columns whatever it hides
- [x] 5.2 The pill is darker: the theme's quiet text blended toward black, not a fixed colour
- [x] 5.3 A lock on the left of the editor's status bar — beside where the content type reads — shows and hides all of the file's secrets: shut while covered, open (and amber) while revealed, absent for files that conceal nothing, with the menu item as the same act's second handle; proven in the two driven screenshots
- [x] 5.4 The per-value click-reveal is removed on review: a click on a cover reveals nothing and posts a notice naming the lock — a click is what a presenter does absentmindedly on the very screen being watched
- [x] 5.5 The lock keeps its shape (drawn at the symbol's own aspect; the open lock was squeezed square) and carries its label: "Secrets hidden" shut, "Secrets shown" open
- [x] 5.6 The feature is a setting — "Conceal secrets" in the editor settings, on by default, registered and reset like every key, applied to already-open tabs the moment it flips
- [x] 5.7 A revealed file covers itself after five untouched minutes — key, click, scroll and edit all reset the clock (one deferred check re-armed for the remainder, never a timer per keystroke), the lock shuts with the covers, and the interval is driver-settable: proven with a 3-second limit, a mid-countdown touch keeping it revealed past the limit, and the covers returning once left alone
- [x] 5.8 A YAML block scalar's lines are covered: `pk: |` carried its RSA key on the following indented lines, which stateless per-line classification drew in the clear — reported with a screenshot. Roles are now computed over the file (`DotenvSecrets.roles(forLines:)`, five tests including the reported shape), recomputed when the document arrives and on every edit, and block-content rows erase whole with a pill each
