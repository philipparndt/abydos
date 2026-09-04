## 1. Writing it down (AbydosKit)

- [ ] 1.1 `ProjectSession` gains the folds: per pane — refs, changes unstaged,
      changes staged, project tree — the keys that were shut and the keys that
      were opened, as two lists rather than one. Optional and additive, absent
      meaning nothing, the shape `pages` and `reviewTicks` have
- [ ] 1.2 `ProjectSession` gains the sidebar tool that was in front, as the name
      of one, and `OpenTerminal` gains whether it was the one in front
- [ ] 1.3 All three are dropped by `filesOnly`: a folder in no working copy
      shares one session with every other such folder, so a fold keyed by a path
      relative to one of them means nothing in the next — and a folder has no
      git tool to be in front
- [ ] 1.4 `isEmpty` still says empty for a session that carries nothing but
      these, so an empty file is still removed rather than written
- [ ] 1.5 The cap: at most 500 keys per tree, shallowest first, applied where
      the session is built rather than at each caller
- [ ] 1.6 `SessionStore.read`/`write` carry all of it; a session file written
      before any of these keys existed still reads, proven on a fixture that
      lacks them

## 2. Getting at it (AbydosApp)

- [ ] 2.1 `BranchesPane` gains a getter and a setter over `collapsedKeys` and
      `openedKeys`, keyed the way `node(forKey:)` already finds a row
- [ ] 2.2 `ChangesPane` gains the same over `Side.collapsed` and `Side.opened`,
      per side
- [ ] 2.3 `ProjectNavigatorViewController` gains one over `expandedPaths()` —
      which already exists and is already the right shape — with the file paths
      written relative to the project root and the `dep:` and `session:`
      identities left as they are
- [ ] 2.4 Each pane takes its folds where it is *built*, in
      `SidebarController.makeToolView`, beside where the changes pane already
      takes the remembered commit message; the project tree takes its folds in
      `load(project:)`, where it presently expands the root alone
- [ ] 2.5 `SidebarController` shows the remembered tool, falling back to the
      project tree where it cannot be built, and without opening a closed
      sidebar
- [ ] 2.6 `BottomPanel.captureTerminals` records which was in front and
      `restoreTerminals` brings that one forward, by name
- [ ] 2.7 `MainWindowController.rememberOpenEditors` and the body of
      `switchProject` capture all of it where they capture the rest
- [ ] 2.8 A key that names no row is dropped on the next capture rather than
      written down for ever

## 3. The page openers that are missing

- [ ] 3.1 `SidebarController.reopen(page:)` gains cases for `launch` and
      `settings`. `sessions` already requires that "the pages whose identity is
      their identifier alone" come back, and these two are written into every
      session file and read by nothing — a requirement that exists and is unmet.
      The `default: break` stays for an identifier a later version wrote

## 4. Proving it

- [ ] 4.1 Kit tests: a session round-trips the folds, the tool and the terminal
      in front; a file without the keys reads as none; the cap keeps the
      shallowest; `filesOnly` drops all three
- [ ] 4.2 A driven run: unfold the working copy, switch to a second project,
      switch back, report the tree — and the same run covers the rebuild the
      report is actually about, since a switch reinstalls the tool through
      `install(tool:force:)` after `readGit()`
- [ ] 4.3 A driven run: leave a project on the refs tree, switch away and back,
      and report which tool is in front and which rail button is lit
- [ ] 4.4 A driven run: four terminals with the third in front, switch away and
      back, report which is in front
- [ ] 4.5 The disk half cannot be driven at all — a driven run deliberately
      reads and writes no session — so it is a kit test on `SessionStore`

## 5. Before finishing

- [ ] 5.1 `make test` clean, `make warnings` clean, machine load said if a bound
      flakes
- [ ] 5.2 No spec is made untrue. `git-refs-tree`'s arrival defaults still hold
      for a project with nothing recorded; `left-rail`'s rule that a button says
      what is on screen is untouched, since restoring a tool changes what is on
      screen and not what the rail means; the driven-run requirement that a
      driven run neither restores a session nor writes one still holds
