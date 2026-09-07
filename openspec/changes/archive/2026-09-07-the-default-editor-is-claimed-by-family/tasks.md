## 1. The claim

- [x] 1.1 `Resources/Info.plist` — `public.text` first among the editor
  entry's kinds. `DeclaredFileTypesTests` still holds: the bundle offers
  rather than claims, and nothing is declared the editor cannot read.
- [x] 1.2 `TypeFamilies.roots(of:)` in the kit, with tests: a list with two
  roots, and the bundle's own identifiers with `public.text` having one.
- [x] 1.3 `DefaultEditor.makeDefault` in two passes: the roots, then what
  `typesThisAppOpens()` still leaves out.

## 2. Finishing

- [x] 2.1 No `.abydos/backlog/spec/*.md` is made untrue: the directory is
  gone from the tree. Not drivable: the dialogs are the system's.
- [x] 2.2 `make test` 4238 tests in 539 suites, exit 0 with the two standing known issues, load 43.0 over 10 cores; `make warnings` exit 0.
