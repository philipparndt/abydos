## 1. The climb, in the engine

- [x] 1.1 Given a file, the nearest ancestor holding a language's root markers,
      bounded by the project root. `markerDirectory` searches downward and stays
      that way for the case with no file in hand; this is the direction it does
      not have.
- [x] 1.2 A file belonging to no subproject answers the project root, which is
      what every file answers today.
- [x] 1.3 A file outside the project answers the project root and does not walk
      to `/`.
- [x] 1.4 Nearest wins where a package contains a package.
- [x] 1.5 Tests as claims, over a fixture with the reported layout — a Swift
      package and three Go modules beside each other:
      `aFileFindsItsOwnPackageWhateverIsScoped`,
      `oneOfThreeModulesAnswersForItsOwnFiles`,
      `aFileInAPlainFolderFallsBackToTheProject`,
      `aPackageInsideAPackageAnswersForItsOwnFiles`.

## 2. The root belongs to the file

- [x] 2.1 Work the root out once, when a file is opened, and carry it with the
      tab.
- [x] 2.2 Convert every editor call site — definition, hover, completions,
      signature help, `opened`, `changed`, rename, usages — to that root.
- [x] 2.3 `grep scopeRoot Sources/AbydosApp/Editor` comes back empty. The
      dangerous outcome is a partial conversion: a file opened under one root and
      asked about under another reaches a server that has never heard of it,
      which looks exactly like the fault being fixed.
- [x] 2.4 A test that the root a file is opened with is the root every later
      question uses.
- [x] 2.5 Switching the scope while a file is open changes nothing about which
      server answers for it.

## 3. What the rest of the app still scopes

- [x] 3.1 Runs, git, launch configurations and the build's module keep using the
      scope. Checked by driving, not by reading the diff — this is the half that
      must not move.
- [x] 3.2 The footer and the preparing chip are keyed by the same root, so they
      say which server is answering about the file in front rather than about the
      pill.

## 4. Watched

- [x] 4.1 The reported case, driven against a scratchpad copy of
      `abydos-examples`, never the checkout: scope on `go-service`, follow
      `Stadium` from `cadova-models/Sources/HexKeyHolder/main.swift`, and land in
      Cadova's own source.
- [x] 4.2 The same with no subproject scoped, which is the case that already
      works — unbroken.
- [x] 4.3 A Go file in the third module, answered by its own module rather than
      by the first found. That fault answers rather than going silent, so it
      needs looking at rather than trusting.
- [x] 4.4 Say how long the second Swift server takes before it answers, beside
      the two minutes already measured for the first.

## 5. Finish

- [x] 5.1 `.abydos/backlog/spec/language-servers.md` says which root a server is
      found and filed under, and that the scope is not it. Name any sentence this
      makes untrue.
- [x] 5.2 `make test` and `make warnings` both clean.
- [x] 5.3 Write down what was ruled out — including falling back from the scope to
      the project root, which fixes the reported silence and leaves the wrong-module
      answer behind it.
- [x] 5.4 Say whether a ceiling on how many servers may run belongs in 0538, with
      what was seen here to inform it.
