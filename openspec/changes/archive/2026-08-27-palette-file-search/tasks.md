## 1. The file list, shared

- [x] 1.1 Make `ProjectSearch.collectFiles()` reachable by something other than
      project search, without copying its exclusion rules — one of the two shapes
      the design leaves open. A test shows both callers skipping a directory
      added to the excluded directories setting.
- [x] 1.2 Add the git source: tracked files from `git ls-files`, relative to the
      work tree root. Tracked only — `--others --exclude-standard` measured
      4.56 s against 0.05 s for one extra file.
- [x] 1.3 Choose between them: git where `GitRepository.discover` finds a work
      tree, the walk where it does not. Tests for both, including a project that
      is a directory with no repository.

## 2. The index

- [x] 2.1 Add the index type in `Sources/AbydosKit/Project` — no view code, and
      testable without a window. It holds paths relative to the project root and
      answers with matches.
- [x] 2.2 Decide its isolation and write the decision down. Today's crash was a
      `Project` written from two threads, so this one is settled deliberately
      rather than assumed.
- [x] 2.3 Build off the main thread, and join a build already in flight rather
      than starting a second — the shape `Project.loadGit` now uses.
- [x] 2.4 Test that building twenty concurrent times builds once and answers
      consistently. Keep the concurrency modest and the suite serialised: thirty-
      two concurrent git callers starved thirty other tests' `git init` two
      commits ago.

## 3. Matching and ranking

- [x] 3.1 Substring match on the path relative to the project root, case
      insensitive.
- [x] 3.2 Rank a match in the last component above a match earlier in the path,
      and an exact name above a longer name containing it. The scenario in the
      spec — `Git` against `Sources/Git/Client.swift` and `Sources/Model/Git.swift`
      — is the test.
- [x] 3.3 Cap the number of files shown, the way `projectLimit` caps projects, so
      branches and actions stay reachable.

## 4. Staying true

- [x] 4.1 Add and remove named paths when `FileSystemChange.namesEveryPath` is
      true.
- [x] 4.2 Mark stale and rebuild once, off the main thread, when it is false —
      never a rebuild per event. A build produces events by the second, and each
      rebuild is a `git ls-files` over the whole repository.
- [x] 4.3 Test that a file created after the index was built is found, and that a
      deleted one stops being listed.
- [x] 4.4 Opening a file that has since been deleted reports it rather than
      opening an empty editor.

## 5. In the palette

- [x] 5.1 Add the `.file` row case beside `.project`, `.branch` and `.action`,
      showing the name with its directory beside it.
- [x] 5.2 Put files in the ranked `everything` scope under their own heading.
      Leave `>` and `:` untouched, and test that they are.
- [x] 5.3 Open the chosen file through `EditorAreaController.open(fileURL:)`, and
      close the palette.
- [x] 5.4 Say "still reading" under the files heading while the first build is in
      flight, and fill the list in when it lands without the palette being
      reopened — an empty list reads as "no such file", which is a different
      answer.

## 6. Finishing

- [x] 6.1 Drive the app against a project of tens of thousands of files and
      record what the first build costs and what typing costs, with the machine
      load beside both. A number without the load cannot be told from a
      regression.
- [x] 6.2 `make test` and `make warnings`, both clean, and the failures compared
      against a baseline taken by stashing the change — the suite carries
      pre-existing environment failures and several load-sensitive tests.
- [x] 6.3 No `.abydos/backlog/spec/*.md` file is made untrue: the backlog was
      dropped on 2026-08-19 and its spec is now `openspec/specs`. Nothing there
      describes the command palette, which is why this change adds a capability
      rather than modifying one.

## What was measured

Driven against a work tree of **24,691 tracked files** under the scratchpad,
built with `BUNDLE_ID=de.rnd7.abydos.palettefiles PIN_UUID=0`, typing `pom.xml`
one character at a time (`--palette-files`):

    FILEINDEX ready after 148.2 ms   24,691 files   load 13.0 over 14 cores (0.9 per core)
    FILEMATCH p        answered 47.79 ms   drew 6.88 ms   8 hits
    FILEMATCH po       answered 11.41 ms   drew 5.33 ms   8 hits
    FILEMATCH pom      answered 12.57 ms   drew 5.42 ms   8 hits
    FILEMATCH pom.     answered  9.93 ms   drew 5.35 ms   8 hits
    FILEMATCH pom.x    answered 12.58 ms   drew 5.67 ms   8 hits
    FILEMATCH pom.xm   answered 10.35 ms   drew 5.88 ms   8 hits
    FILEMATCH pom.xml  answered 13.30 ms   drew 5.69 ms   8 hits

`answered` is what the index cost off the main thread; `drew` is what the main
thread paid to put the rows on screen. The first keystroke is dearer because it
is the one that waits on the last of the build.

**The first version of this was four times slower and the unit test did not
say so.** Matching was written against `[String]`, lower-casing every path and
taking its last component through `NSString` on each keystroke. The same driven
run read **110–157 ms per character** while `FileMatchingTests` read 25 ms for
25,000 synthetic paths — paths a third the length of real ones, which is where
the rest of it was hiding. Preparing each path once when the index is built, and
searching lower-cased UTF-8 bytes through a buffer pointer rather than
`String.range(of:)`, took the unit measurement from 25 ms to **8.4 ms** and the
driven one to **10–13 ms**. `preparingOnceIsWhyTypingIsAffordable` prints both
numbers side by side so the next person need not take that on trust.

`make test`: the change's failures are a strict subset of the baseline's at
matched load — 9 distinct against the baseline's 8–10 across two stashed runs,
all of them pre-existing container, agent-session and diagram-runtime failures.
One earlier run at load 25 produced a cluster of `GitStash`/`GitBackup` failures
and an index-out-of-range in `droppingSeveralTakesTheOnesThatWereChosen`; those
suites pass in isolation with the change and did not recur at load 15, and the
crash is that test indexing `entries[0]` without requiring the list first.

`make warnings`: clean, exit 0.
