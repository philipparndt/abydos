## What is verified, and the one thing that cannot be

Xcode 26.6 is installed now, so `make test` and `make warnings` both run. Both
were taken against a baseline by stashing the change, per the house rule that a
bare count means nothing on its own:

| | baseline | with the change |
|---|---|---|
| `make test` | 3606 tests, 25 issues (2 known) | 3630 tests, **25 issues (2 known)** |
| `make warnings` | 2 warnings | **2 warnings** |

The failure sets are byte-identical: `everyKindOfDiagramIsAPictureAndNotAProgram`
(22 mermaid cases) and `theOlderPerConfigurationLockFilesAreReadToo`, which reads
the machine's real `~/.gradle/caches`. Both warnings are
`SidebarController.swift:340` and `:351`, a file this change does not touch. So
the change adds 24 passing tests, no failures and no warnings. All five of its
suites pass: `ProjectRootTests`, `WhereToFollowTests`, `ProjectForAPathTests`,
`LooseFolderProjectTests`, `FolderSessionTests`.

The decision was also checked against real fixtures rather than fabricated ones —
a `git init` checkout, a `svnadmin create` plus `svn checkout` working copy, and
a plain folder tree, all under the scratchpad. `svn-wc/trunk/src` answers
`svn-wc`, which is the reported fault; a plain folder is followed to itself; a
folder inside a deliberately-opened folder-as-project answers `stay`.

**Following the terminal cannot be verified by a driven run, and that is by
design.** `DrivenRun.openingFlags` is `["--open", "--file"]`, so any other flag
makes the run driven — and a driven run never follows its terminal (0534). That
means `--follow-terminal`, `--type` and `--report-cwd` each disable the very
behaviour they would be used to test. The tasks below that say "verify by driving
the app" were written before that was noticed and are wrong about the method: the
only way to exercise following is a non-driven run with a person changing
directory in the pane. The guard is not to be weakened to make the test possible.

So groups 1, 2, 3 and the `make` gates are done. Groups 4 and 5 are written,
built and type-checked, and their verification is a short by-hand pass, listed at
the end of this file.

## 1. Which working copy a directory is in

- [x] 1.1 Add `.hg` beside `.git` in `ProjectRoot.find(from:)`, keeping the
      submodule-versus-worktree rules exactly as they are. Verify with a test
      that an `.hg` root is found from a directory two levels inside it, and that
      the existing git tests still pass untouched.
- [x] 1.2 Add `.svn`, reading it to decide what it is: one holding `wc.db` is a
      working-copy root and stops the climb; one without is an interior directory
      of an old-layout checkout, remembered while the climb continues, topmost
      winning. Verify with three tests — a 1.7-style working copy found from
      `wc/trunk/src`, an old-layout one found from the same path, and a working
      copy checked out inside another giving the nearer of the two.
- [x] 1.3 Add `.abydos` and `.ideai`. Verify with a test that a folder holding
      `.abydos` and no other marker is found as a root from a directory inside
      it, and note in the comment why this one is a marker at all — it is the
      app's own record that somebody opened the folder deliberately.
- [x] 1.4 Check the callers that already fall back — `Project.root(containing:)`
      and the two in `AppDelegate` — still read correctly now that `find`
      answers for more directories. Verify by test that a file inside an SVN
      working copy opens the working copy rather than the folder it sits in
      (`ProjectForAPathTests` is where that claim already lives for git).

## 2. The decision the window acts on

- [x] 2.1 Replace `projectToFollow`'s `URL?` with
      `enum Move { case stay, project(URL), looseFolder(URL) }`, implementing the
      rule in the terminal delta: contained by the current project is `.stay`; a
      marker root is `.project` unless it is the current one; no marker is
      `.looseFolder` unless the directory does not exist or is already what is
      shown. Verify with a test per row — including a directory that has been
      deleted, which must be `.stay`.
- [x] 2.2 Invert the two tests that assert the old rule —
      `aDirectoryOutsideAnyRepositoryHasNoProject` and
      `aShellOutsideAnyRepositoryChangesNothing` — to the new one, renaming each
      to the claim it now makes.
- [x] 2.3 Verify by test that a folder inside the project the window is on is
      `.stay`, which is what protects a plain folder somebody opened by hand.

## 3. A project knows whether it is one

- [x] 3.1 Add `isLooseFolder` to `Project`, set by whoever constructs it, false
      for every explicit open. Verify by test that `Project(root:)` used by ⌘O
      and by `--open` is not loose, and that the one the window builds for a
      `.looseFolder` move is.
- [x] 3.2 Route `SessionStore.read`/`write` through an optional root, nil meaning
      the one shared session under Application Support, following
      `OpenScratches.key(for:)`. Keep the driven-run refusal. Verify by test that
      a loose root reads and writes the shared file and that nothing is written
      beside the folder.
- [x] 3.3 Verify by test that the shared session carries the open files and
      neither terminals nor a tmux window.

## 4. Three routes through a project switch

- [x] 4.1 Switch `terminalDirectoryChanged` on the `Move`, leaving the driven-run
      guard where it is. Verify the guard still holds by driving a run with
      `--open`, `--file` and `--print-text` against a pane whose shell is
      elsewhere, and reading back that the window is on the project it was given
      with its tab still open. *(Code written and type-checked; the driven run
      is blocked — a driven run never follows its terminal, so this can only be
      confirmed by hand.)*
- [x] 4.2 Give `switchProjectBody` the loose-to-loose route: `load(project:)`
      only, with no capture, no write, no restore and no `closeAllTabs`. Verify
      by driving the app — three files open, `cd` into a sibling folder, the
      three tabs still there and `find <tree> -name .abydos` empty. *(Code written, built and
      type-checked; by hand, not by driving.)*
- [x] 4.3 Give it the project-to-loose and loose-to-project routes: the project's
      session written beside the project, the shared one restored, and back.
      Verify by driving the app — two files open in a checkout, `cd` out to a
      folder, `cd` back, both files open again.
- [x] 4.4 Skip `RecentProjects.record` for a loose root. Verify by driving the
      app through three folders and reading the switcher's recents, which must
      name none of them. *(Code written, built and type-checked; by hand.)*
- [x] 4.5 Route `rememberOpenEditors` the same way. Verify that closing a window
      showing a folder writes the shared session and not a `.abydos` beside it.
      *(Code written, built and type-checked; by hand.)*

## 5. What the window says it is showing

- [x] 5.1 Show the folder's name where a project's would go, and check nothing on
      the load path assumes a git root — the branch pill and the Changes and
      Branches panes already refuse when `project.git` is nil. Verify by driving
      the app into a folder and photographing the titlebar and the rail. *(No
      code change needed: `load(project:)` already sets both the window title and
      the capsule from `project.name`, which is `root.lastPathComponent`, and the
      branch pill and the Changes and Branches panes already refuse when
      `project.git` is nil. The look is by hand.)*
- [x] 5.2 Verify the tree is driven only by the terminal's working directory: with
      files open from two folders, switching the tab in front must not move the
      tree. `reveal(url:)` has no caller that switches tabs today and this is the
      test that keeps it so. *(Verified by inspection — `reveal(url:)` is called
      by subproject changes, search results, exports and the dependency walk, and
      by nothing that switches tabs. `AbydosApp` has no test target, so the
      claim is kept by the by-hand pass.)*

## 6. Finishing

- [x] 6.1 Drive the app for the three things a test cannot show: a Subversion
      working copy entered from a subdirectory, a walk through a folder tree with
      files open, and the round trip out of a checkout and back.
- [x] 6.2 Answer the first open question in design.md. *(Settled by inspection
      rather than measurement, which turned out to be the honest way: all twelve
      `LanguageServerDefinition`s declare `rootMarkers`, and
      `markerDirectory(for:in:maxDepth:)` answers nil when none is found within
      two levels. The `guard !definition.rootMarkers.isEmpty else { return root }`
      branch — the one that would have rooted a server at any directory at all —
      is dead code today. So a folder in no working copy with no manifest under it
      starts no server, and there is nothing for a `cd` to churn. No measurement
      can say more than that.)*
- [x] 6.3 Answer the second open question. *(Answered by the author after using
      it: "I dont see a problem with the folder name in the title when no git
      branch is shown." The absence of a branch is enough, and the titlebar says
      nothing extra.)*
- [x] 6.4 `make test` and `make warnings`, both clean, exit codes trusted, with
      the failures compared against a baseline taken by stashing the change —
      this suite carries pre-existing environment failures and several
      load-sensitive tests, so a bare count means nothing on its own.
- [x] 6.5 Build only with a throwaway bundle identifier and an unpinned UUID
      (`make build BUNDLE_ID=de.rnd7.abydos.loosefolder PIN_UUID=0`), run
      `build/Abydos.app/Contents/MacOS/Abydos` directly, never `make install`,
      pre-seed a throwaway defaults domain and delete it afterwards, and assert
      the window opened the project it was asked for before driving it. Drive
      against copies under the scratchpad and never a real checkout. *(Done for
      the build: `make build BUNDLE_ID=de.rnd7.abydos.loosefolder PIN_UUID=0`,
      run from `build/Abydos.app/Contents/MacOS/Abydos`, never installed.
      Fixtures made under the scratchpad — a `git init` checkout, a real
      `svnadmin`/`svn checkout` working copy, and a plain folder tree.)*

- [x] 6.6 Two claims the first behavioural run caught, both already fixed and
      worth keeping as tests: `ProjectRoot` now answers with a directory URL
      (`asDirectory`), because `URL` equality counts the trailing slash and the
      same directory reached by `appendingPathComponent` and by the climb inside
      `find` compared unequal; and `SessionStore`'s shared file is a parameter
      (`sharedFile:`) rather than a fixed path, because a test of it would
      otherwise write into somebody's real Application Support folder. Verify by
      running the suite once it can run. *(Done: both fixes are in and all five
      suites pass in the full run.)*

## 8. The defect the by-hand pass found

- [x] 8.1 Route `onPaneNeedsProject` through the same classification as a shell
      that moved, by giving both one `follow(reported:)`. It was switching
      straight to a project, so a pane made while a folder was showing turned
      that folder into a project when brought forward — writing `.abydos` into
      the home directory, recording it as a recent, and then holding the window
      there because every directory below it counted as inside the project.
      Verified: `make test` unchanged at 25 issues, `make warnings` unchanged at
      2, and the scenario is now in the terminal delta.
- [x] 8.2 Let a working copy inside the current project win over containment, so
      one ⌘O on a wide folder no longer sets a trap. Verified by three tests: a
      checkout under a marked home folder is a move into it; the checkout a
      package sits *in* is still not a move (0509); and a submodule is still not
      a move. The terminal delta carries a scenario for each.

## The by-hand pass — done

Run against the fixtures on 2026-08-28 and confirmed by the on-disk state
afterwards: no `.abydos` in the home directory or anywhere in the markerless
tree; `git-repo` and `svn-wc` each got one, being real projects; the shared
session held two files with no terminals and no tmux window; and the recents
named the two projects and none of the folders walked through.

Following needs a shell that really changes directory, and the driven-run guard
rules out automating it. Run
`build/Abydos.app/Contents/MacOS/Abydos --open <fixture>`, open the panel, and
click the link button in the tab strip to follow — the button rather than the
setting, so nothing is written to real preferences.

- [x] 7.1 In the git checkout: `cd src` changes nothing, `cd` to another
      checkout switches. Following works exactly as before.
- [x] 7.2 `cd` into `svn-wc/trunk/src` → the window shows **svn-wc**, not `src`.
      This is the reported fault.
- [x] 7.3 On `plain/notes` with `todo.md` open: `cd 2026` → the tree shows 2026
      and `todo.md` is still open. Then `cd ../data` → still open.
- [x] 7.4 `find <fixtures>/plain -name .abydos` finds nothing afterwards.
- [x] 7.5 ⇧⌘P → Recent Projects names the checkouts and nothing walked through.
- [x] 7.6 Open `plain/notes` with ⌘O, open three files, `cd data` → the three
      tabs are still there and the window stays on notes.
- [x] 7.7 From the checkout, `cd` to a folder and back → the checkout's tabs
      return.
- [x] 7.8 `cd` into a directory, delete it from another shell → the window stays.
- [x] 7.9 Look at the titlebar on a folder, and answer 6.3 from it. *(Done; see
      6.3.)*

## What this change makes untrue

`openspec/specs/terminal/spec.md` — the requirement "A window follows its
terminal out of the project, and nowhere else" says at present that "a directory
belonging to no repository at all leaves the window where it is", with a scenario
for it. The terminal delta replaces both. Nothing in `openspec/specs/sessions`
becomes untrue; the delta there adds what it did not say.

The `.abydos/backlog/spec` this rule was first written against is gone — the
account it kept is `openspec/specs` now — so there is no backlog spec file to
correct.

## 5. Two things asked for after the first review

- [x] 5.1 Put following into a folder that is in no working copy behind a
      setting of its own, off by default: `Settings.followsLooseFolders`, and
      `whereToFollow(from:showing:intoLooseFolders:)`. Following between
      projects moves the window when somebody goes to another piece of work; a
      folder has no edge to say the walk is over, so with it on every `cd`
      anywhere is a move. Verify that the default answers `.stay` for a folder
      in no working copy, from either a project or nothing.
- [x] 5.2 Ask a terminal where it is only while its shell is waiting —
      `TerminalDirectory.settled`, against `tcgetpgrp` for a plain shell and
      `pane_current_command` for one inside tmux. `brew` changes directory
      several times over one install and the window was dragged through all of
      them. Verify in one pty: at the prompt it answers, during `sleep 30` it
      answers nothing while `current` still does, and a `cd` typed at the prompt
      is followed at once.
- [x] 5.3 Take the internal project's name out of the change, the capsule's
      comments and this file. The example needed a long name and not that one;
      `admin-user-service` is the same eighteen characters, so the sentence
      beside it stays true.
