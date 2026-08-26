## 1. The check, before the work it measures

- [x] 1.1 Write `Scripts/file-size.sh`: walk `Sources` for `.swift`, compare each
      against `Scripts/file-size-allowed.txt` (`<lines> <path>`, sorted), print
      every fault sorted by excess, exit non-zero if any
- [x] 1.2 Record today's twenty-seven files over 1,000 lines in
      `Scripts/file-size-allowed.txt`, at the lengths they are now
- [x] 1.3 Say in the script's header why the list exists — 44,296 lines of
      excess, and that a check failing on all of it gets switched off the same
      afternoon
- [x] 1.4 Wire it into `Scripts/warnings.sh` so `make warnings` runs it and its
      exit code counts
- [x] 1.5 Prove the four cases by hand: unlisted file over the line fails; a
      listed file grown fails with both numbers; a listed file shortened passes;
      a listed file under 1,000 is reported as strikeable
- [x] 1.6 **Amended after group 4:** one hard number made the arithmetic the
      goal, so the rule is now an aim of 1,000 and a limit of 1,100. A file
      between them is reported and passes. Spec and check both updated, and the
      two new cases proven by hand at 1,050 and 1,150 lines.

## 2. The driving verbs that only forward

- [x] 2.1 Move the editor's driving verbs (`editorTextForTesting`,
      `selectLinesForTesting`, the completion and navigation exercises, the
      undo tree) to `EditorAreaController` or `EditorViewController`
- [x] 2.2 Move the terminal and panel driving verbs to `BottomPanel` and
      `TerminalView`, keeping them under the ceiling as they arrive
- [x] 2.3 Move the navigator and scratch driving verbs to
      `ProjectNavigatorViewController` and the scratches pane
- [x] 2.4 ~~Move the git-pane driving verbs to `ChangesPane`, `BranchesPane` and
      `HistoryPane`~~ — **not possible here.** Measured: every one of them calls
      `showSidebarTool` to bring its pane up first, so none closes over the
      panes alone. They move in step 5.3, with the method they need. The same
      holds for six panel verbs that call `setPanelVisible`; those wait for 8.1.
- [x] 2.5 Point `AppDelegate` and `LaunchOptions` dispatch at the sub-controller
      through the window's existing accessors; delete the empty forwards
- [x] 2.6 Run every launch flag whose verb moved and confirm identical output
- [x] 2.7 `make test` and `make warnings` green; update the recorded length for
      `MainWindowController.swift` and any file that grew

## 3. ResultsPresenter

- [x] 3.1 New `Sources/AbydosApp/Results/ResultsPresenter.swift` owning
      `usagesWindow`, `searchWindow`, `usagesPlacement`, `searchPlacement`,
      `lastUsagesRequest`, `usagesPane` and `symbolPalette`
- [x] 3.2 Move usages, search results, renaming a symbol and copying a link to
      it, with the driving verbs that read that state
- [x] 3.3 Hand it the editor and the bottom panel at construction; give it
      closures for what it must tell the window — no reference back to
      `MainWindowController`
- [x] 3.4 Leave the `@objc` actions on the window controller as one-line
      forwards
- [x] 3.5 `make test`, `make warnings`, and the driven usages and search flags
- [x] 3.6 **Finding: the section is three concerns, not one.** The design put
      renaming and copying a link in this collaborator. Measured, those 1,100
      lines are three things that share no state: results presentation (the
      seven properties, ~430 lines, done here), the language server's *edit*
      actions (rename, code actions, workspace edits, ~350 lines, on the editor
      and the navigator), and code links (copy and follow a place, ~180 lines,
      on the project). Lumping them would have made one class at the ceiling
      and cohesive in nothing. The other two are groups 10 and 11.

## 4. TitlebarController

- [x] 4.1 New `Sources/AbydosApp/Titlebar/TitlebarController.swift` owning the
      capsule, the four pills, `worktrees`, `branchRead`, `pilledContainer`,
      the backdrop and the seam
- [x] 4.2 Move the `NSToolbarDelegate` conformance to it and set it as the
      toolbar's delegate directly — it does not stay on the window controller
- [x] 4.3 Move the devcontainer pill and its menu, and the worktree and
      subproject menus
- [x] 4.4 ~~Split it if it exceeds the ceiling~~ — not needed. It came to 974
      lines once the run item and the branch popover went back to the window,
      so it stays one file and one type
- [x] 4.5 `make test`, `make warnings`, `reportToolbarForTesting` and
      `highlightPillsForTesting` unchanged
- [x] 4.6 **Three things stayed behind, each for a reason worth recording.**
      `branchRead` is the window's, because `readGit` orchestrates far more than
      the pill and the titlebar only needs the answer — it is injected.
      `showBranchMenu` is the window's because `ProjectSwitcherPopover.show`
      takes a `MainWindowController?` as its owner. The run toolbar item is the
      window's because every button on it is about running; the titlebar asks
      for it through `makeRunItem` and will stop having to at group 7.
- [x] 4.7 `titlebarContainer` was declared and never read. Swift does not warn
      about an unused property, so it had sat there unnoticed; deleted.

## 5. SidebarController

- [x] 5.1 New `SidebarController` as an `NSViewController`, owning the tool
      strip, the five panes, the popover and the sidebar split
- [x] 5.2 **Answered: neither — it is not an `NSViewController` at all.** The
      rail is a subview of the window's root and the tool it opens lives inside
      `navigatorContainer`, on the far side of a split view. There is no one
      view for it to control, so it owns the pieces and the window keeps
      building the hierarchy — which also means 5.4's assumption fails.
- [x] 5.3 Move the git log and commit pages and the diff apply, stash and
      discard verbs, and with them the git-pane driving verbs deferred from 2.4
      — they need `showSidebarTool`, which arrives here
- [x] 5.4 ~~Its `@objc` actions go on it~~ — **wrong, and 5.2 is why.** It is
      not in the responder chain, so `showLogPage`, `showCommitPage` and
      `toggleCommitFilesByFolder` stay on the window as one-line forwards, the
      same as the titlebar's. The menu bar reaches them by selector and would
      have gone grey otherwise.
- [x] 5.5 `make test`, `make warnings`, and the driven sidebar and git flags

## 6. DebugCoordinator

- [x] 6.1 New `DebugCoordinator` owning `pendingBreakpoints`,
      `executionMarker` and `anchoringWork`
- [x] 6.2 Move breakpoint management, the execution marker and going to a place
      in the code, with their driving verbs
- [x] 6.3 Keep the terminal-shortcut half of `validateMenuItem` on the window —
      it is about keyboard focus, not about debugging
- [x] 6.4 `make test`, `make warnings`, and the driven debug flags including
      `--debug-stop` and `--debug-finish`

## 7. The run cluster

- [ ] 7.1 `RunConfigurationDiscovery` — `refreshRunConfigurations`, the scan
      re-entry flags, `xcodeDestinations`
- [ ] 7.2 `RunCoordinator` — choosing and starting: `run`, `debug`, `startRun`,
      `startDebug`, `startJavaDebug`, `startScriptDebug`, `runScheme`,
      profiling and coverage, `runningPane`
- [ ] 7.3 `LaunchConfigurationMenu` — `runList`, the make goals, the
      configuration editor and the destination menu
- [ ] 7.4 `HotSwapCoordinator` — `compileForHotSwapIfDebugging`, the compile
      queue, the once-per-session refusal
- [ ] 7.5 `ClusterRun` — `runInCluster`, `installDevPod`, the forwards, the
      profiler address and the service port
- [ ] 7.6 Decide which of these the window holds and which are peers, per the
      design's open question
- [ ] 7.7 `make test`, `make warnings`, and every driven run, debug, profile and
      make-goal flag

## 10. Server edit actions

- [ ] 10.1 New `Editor/ServerActions.swift` owning renaming a symbol, offering
      and taking code actions, and applying a workspace edit — `renameSymbol`,
      `offerCodeActions`, `takeServerEdits`, `apply`, `remember`,
      `workspaceEditFiles`, `completeAtCaret`, `symbolName`
- [ ] 10.2 It is handed the editor and the navigator; `findUsages`, `symbols`
      and `reasonForNoSymbols` come with it, and `ResultsPresenter`'s three
      closures are wired to it rather than to the window
- [ ] 10.3 `make test`, `make warnings`, and the driven rename and code-action
      flags

## 11. Code links

- [ ] 11.1 New `CodeLinks.swift` owning copying and following a place —
      `copyLink`, `copyReference`, `copyPermalink`, `goToCopiedPlace`, `follow`,
      `copyToPasteboard`, and their driving verbs
- [ ] 11.2 `make test`, `make warnings`, and the driven copy-link and
      follow-link flags

## 8. The window controller itself

- [ ] 8.1 Move `NSSplitViewDelegate` and the panel geometry to
      `MainWindowController+Layout.swift`
- [ ] 8.2 Move the 108 forwarding actions and `validateMenuItem` to
      `MainWindowController+MenuActions.swift`
- [ ] 8.3 Confirm the only members left at internal visibility are the
      collaborators — no field widened from `private` to make a split work
- [ ] 8.4 `MainWindowController.swift` under 1,000 lines; strike it from
      `Scripts/file-size-allowed.txt`
- [ ] 8.5 `make test` and `make warnings` green

## 9. Proving nothing changed

- [ ] 9.1 Run `Scripts/screenshots.sh` and compare every picture against the
      ones in `docs/images`
- [ ] 9.2 Walk the menus in a driven run and confirm no item that was enabled is
      now grey
- [ ] 9.3 Open a project, switch to another and back, and confirm
      `ProjectSessions` restores the layout it did before
- [ ] 9.4 Confirm the recorded list is shorter by one and no entry has grown
