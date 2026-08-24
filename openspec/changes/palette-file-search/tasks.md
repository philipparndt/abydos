## 1. The file list, shared

- [ ] 1.1 Make `ProjectSearch.collectFiles()` reachable by something other than
      project search, without copying its exclusion rules — one of the two shapes
      the design leaves open. A test shows both callers skipping a directory
      added to the excluded directories setting.
- [ ] 1.2 Add the git source: tracked files from `git ls-files`, relative to the
      work tree root. Tracked only — `--others --exclude-standard` measured
      4.56 s against 0.05 s for one extra file.
- [ ] 1.3 Choose between them: git where `GitRepository.discover` finds a work
      tree, the walk where it does not. Tests for both, including a project that
      is a directory with no repository.

## 2. The index

- [ ] 2.1 Add the index type in `Sources/AbydosKit/Project` — no view code, and
      testable without a window. It holds paths relative to the project root and
      answers with matches.
- [ ] 2.2 Decide its isolation and write the decision down. Today's crash was a
      `Project` written from two threads, so this one is settled deliberately
      rather than assumed.
- [ ] 2.3 Build off the main thread, and join a build already in flight rather
      than starting a second — the shape `Project.loadGit` now uses.
- [ ] 2.4 Test that building twenty concurrent times builds once and answers
      consistently. Keep the concurrency modest and the suite serialised: thirty-
      two concurrent git callers starved thirty other tests' `git init` two
      commits ago.

## 3. Matching and ranking

- [ ] 3.1 Substring match on the path relative to the project root, case
      insensitive.
- [ ] 3.2 Rank a match in the last component above a match earlier in the path,
      and an exact name above a longer name containing it. The scenario in the
      spec — `Git` against `Sources/Git/Client.swift` and `Sources/Model/Git.swift`
      — is the test.
- [ ] 3.3 Cap the number of files shown, the way `projectLimit` caps projects, so
      branches and actions stay reachable.

## 4. Staying true

- [ ] 4.1 Add and remove named paths when `FileSystemChange.namesEveryPath` is
      true.
- [ ] 4.2 Mark stale and rebuild once, off the main thread, when it is false —
      never a rebuild per event. A build produces events by the second, and each
      rebuild is a `git ls-files` over the whole repository.
- [ ] 4.3 Test that a file created after the index was built is found, and that a
      deleted one stops being listed.
- [ ] 4.4 Opening a file that has since been deleted reports it rather than
      opening an empty editor.

## 5. In the palette

- [ ] 5.1 Add the `.file` row case beside `.project`, `.branch` and `.action`,
      showing the name with its directory beside it.
- [ ] 5.2 Put files in the ranked `everything` scope under their own heading.
      Leave `>` and `:` untouched, and test that they are.
- [ ] 5.3 Open the chosen file through `EditorAreaController.open(fileURL:)`, and
      close the palette.
- [ ] 5.4 Say "still reading" under the files heading while the first build is in
      flight, and fill the list in when it lands without the palette being
      reopened — an empty list reads as "no such file", which is a different
      answer.

## 6. Finishing

- [ ] 6.1 Drive the app against a project of tens of thousands of files and
      record what the first build costs and what typing costs, with the machine
      load beside both. A number without the load cannot be told from a
      regression.
- [ ] 6.2 `make test` and `make warnings`, both clean, and the failures compared
      against a baseline taken by stashing the change — the suite carries
      pre-existing environment failures and several load-sensitive tests.
- [ ] 6.3 No `.abydos/backlog/spec/*.md` file is made untrue: the backlog was
      dropped on 2026-08-19 and its spec is now `openspec/specs`. Nothing there
      describes the command palette, which is why this change adds a capability
      rather than modifying one.
