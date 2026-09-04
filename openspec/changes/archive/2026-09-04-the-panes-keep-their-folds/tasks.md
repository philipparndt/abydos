## 1. Writing it down (AbydosKit)

- [x] 1.1 `ProjectSession` gains the folds: per pane — refs, changes unstaged,
      changes staged, project tree — the keys that were shut and the keys that
      were opened, as two lists rather than one. Optional and additive, absent
      meaning nothing, the shape `pages` and `reviewTicks` have
- [x] 1.2 `ProjectSession` gains the sidebar tool that was in front, as the name
      of one, and `OpenTerminal` gains whether it was the one in front
- [x] 1.3 All three are dropped by `filesOnly`: a folder in no working copy
      shares one session with every other such folder, so a fold keyed by a path
      relative to one of them means nothing in the next — and a folder has no
      git tool to be in front
- [x] 1.4 `isEmpty` still says empty for a session that carries nothing but
      these, so an empty file is still removed rather than written
- [x] 1.5 The cap: at most 500 keys per tree, shallowest first, applied where
      the session is built rather than at each caller
- [x] 1.6 `SessionStore.read`/`write` carry all of it; a session file written
      before any of these keys existed still reads, proven on a fixture that
      lacks them

## 2. Getting at it (AbydosApp)

- [x] 2.1 `BranchesPane` gains a getter and a setter over `collapsedKeys` and
      `openedKeys`, keyed the way `node(forKey:)` already finds a row
- [x] 2.2 `ChangesPane` gains the same over `Side.collapsed` and `Side.opened`,
      per side
- [x] 2.3 `ProjectNavigatorViewController` gains one over `expandedPaths()` —
      which already exists and is already the right shape — with the file paths
      written relative to the project root and the `dep:` and `session:`
      identities left as they are
- [x] 2.4 Each pane takes its folds where it is *built*, in
      `SidebarController.makeToolView`, beside where the changes pane already
      takes the remembered commit message; the project tree takes its folds in
      `load(project:)`, where it presently expands the root alone
- [x] 2.5 `SidebarController` shows the remembered tool, falling back to the
      project tree where it cannot be built, and without opening a closed
      sidebar
- [x] 2.6 `BottomPanel.captureTerminals` records which was in front and
      `restoreTerminals` brings that one forward, by name
- [x] 2.7 `MainWindowController.rememberOpenEditors` and the body of
      `switchProject` capture all of it where they capture the rest
- [x] 2.8 A key that names no row is dropped on the next capture rather than
      written down for ever

## 3. The page openers that are missing

- [x] 3.1 `SidebarController.reopen(page:)` gains cases for `launch` and
      `settings`. `sessions` already requires that "the pages whose identity is
      their identifier alone" come back, and these two are written into every
      session file and read by nothing — a requirement that exists and is unmet.
      The `default: break` stays for an identifier a later version wrote

## 4. Proving it

- [x] 4.1 Kit tests: a session round-trips the folds, the tool and the terminal
      in front; a file without the keys reads as none; the cap keeps the
      shallowest; `filesOnly` drops all three
- [x] 4.2 A driven run: unfold the working copy, switch to a second project,
      switch back, report the tree. Identical before and after —
      `▾ Working copy · 1` over `▸ Unstaged (1)` — and the negative control
      holds: untouched, the working copy still arrives `▸`.

      **It caught the capture being wrong.** Reading the pane's two sets
      records what somebody *decided*, and the outline holds the rest: a
      section nobody has touched is shut because a fresh row is not expanded,
      not because it is in `collapsedKeys`. Restored from the sets, the tree
      came back with everything not explicitly shut open. The capture now
      walks the rows and asks the two questions `restoreExpansion` asks.
- [x] 4.3 A driven run: `--sidebar branches`, switch away and back,
      `RAIL: panel=closed tool=branches …`. The rail's report gained the tool's
      name, because the rail has no branches button and the answer could not be
      read anywhere.
- [x] 4.4 A driven run: three terminals with the third in front, switch away,
      close them all, switch back — `tmux | Local | *Local | Local` before and
      after.

      **Two things it caught.** A switch does not tear terminals down at all
      ("a terminal is a place somebody is"), so the first run never reached
      the restore and had to close them first. And matching the one in front
      *by name* brought back the first of three called `Local`: the design
      ruled out an index because a terminal that fails to start shifts them,
      and a name has the same shape of fault. The session object is held as it
      is created instead, which is neither.
- [x] 4.5 The disk half cannot be driven at all — a driven run deliberately
      reads and writes no session — so it is a kit test on `SessionStore`

## 5. Before finishing

- [x] 5.1 `make test` 4046 tests in 515 suites, exit 0, at load 22 over 14
      cores; `make warnings` exit 0. No bound flaked.
- [x] 5.2 No spec is made untrue. `git-refs-tree`'s arrival defaults still hold
      for a project with nothing recorded; `left-rail`'s rule that a button says
      what is on screen is untouched, since restoring a tool changes what is on
      screen and not what the rail means; the driven-run requirement that a
      driven run neither restores a session nor writes one still holds
