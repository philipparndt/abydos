# Split the window controller

## Why

`MainWindowController.swift` is **13,030 lines**: one `final class`, 674
members, 535 functions and 131 properties in a single scope. It is the largest
file in the repository by a factor of two and a half, and it has stopped having
a shape anybody can navigate.

The evidence is in the file's own section headings. It carries 29 `// MARK`
sections, and the one titled **Zoom** is 1,576 lines long — three `@objc`
zoom verbs followed by the entire sidebar tool host, the git log and commit
pages, the diff apply/stash/discard verbs, and some sixty driving verbs. The
headings no longer describe what is under them, which is what a file looks like
once it is only ever appended to.

Two separate things made it that size, and they want different remedies.

**A driving surface that belongs elsewhere — 3,749 lines, 28% of the file.**
193 members named `…ForTesting`. The AppKit target cannot be reached from the
suite, so `LaunchOptions` flags drive the real window through these methods;
this is the machinery `openspec/specs/screenshots` describes and it is entirely
legitimate. It is simply not declared beside the thing it drives. 149 of those
members — 2,575 lines — touch nothing but the sub-controllers they forward to
(`editor`, `bottomPanel`, `navigator`, the panes). They are on the window
controller because that is where the flag arrives, not because it is theirs.

**A god object — the remaining 9,300 lines.** 131 properties in one scope means
every one of the 535 methods can reach every one of them. Measured against what
the methods *actually* touch, the clusters are far smaller than the scope that
holds them, and they barely overlap:

| cluster | lines | state held exclusively by it |
|---|---|---|
| running, launch configurations, hot code replace, cluster | **5,117** | `runControl`, `runConfigurations`, `launchConfigurations`, `selectedConfiguration`, `devPodClient`, `devPodForwards`, `hotSwapCompile*`, `profileAfterRun`, `scriptDebugExit` |
| the sidebar tools and git pages | ~1,600 | `changesPane`, `branchesPane`, `structurePane`, `scratchesPane`, `historyPane`, `toolPopover`, `logPage`, `commitPage` |
| the titlebar pills and the devcontainer | ~1,300 | `capsule`, `subprojectPill`, `worktreePill`, `devContainerPill`, `worktrees`, `branchRead`, `pilledContainer` |
| debugging, and going to a place in the code | ~1,100 | `pendingBreakpoints`, `executionMarker`, `anchoringWork` |
| usages, search results, renaming, copying a link | ~1,100 | `usagesWindow`, `searchWindow`, `usagesPlacement`, `searchPlacement`, `lastUsagesRequest` |

The window controller is not doing five jobs badly. It is holding five
collaborators' state in one lexical scope and letting anything reach it.

**What this is not about: build time.** It was the obvious justification, so it
was measured before it was believed. Warm incremental rebuilds at load 8–12:
touching `MainWindowController.swift` (13,030 lines) took 13.04 s and 9.54 s,
and touching `Toast.swift` (611 lines) took 10.36 s. `AbydosApp` is compiled
whole-module — one `AbydosApp.o` — so *any* file in it rebuilds all of it, and
file size does not enter into it. The argument is legibility and encapsulation,
and it should not be dressed up as a performance one.

There is no originating `.abydos/backlog` item; the backlog was retired before
this was raised.

## What changes

**A ceiling on the size of a source file, kept by a check rather than by
anybody remembering it.** No Swift source file exceeds 1,000 lines. 27 files in
`Sources` are over it today, 71,296 lines between them — 44,296 lines of
excess — so the check begins with a recorded list of what is already over and
fails only on a file getting *worse* or a new one arriving over the line. That
list is what the work then empties, and a rule with no exceptions left in it is
one the check can tighten to.

**`MainWindowController` keeps what a window controller is for** — the window
and its delegate methods, the split layout, opening a project, menu validation
— and delegates the rest. Target: about 1,000 lines.

**Five collaborators that own their state**, each following the
`EditorAreaController` precedent already in the tree: a façade the window talks
to, which owns its own subtree and is unaware there is a window controller
above it. Running (further split, since it alone is 5,117 lines), the sidebar,
the titlebar, debugging, and results.

**Each driving verb is declared beside the thing it drives**, and moves with
it. The 44 driving verbs that reach past the sub-controllers reach for state
that is moving into a collaborator anyway, so they follow it rather than
needing a way back in.

Explicitly **not** done: splitting the class into `extension
MainWindowController` files. Swift's `private` is visible only within the
declaring file, so that move forces all 131 properties to `internal` — smaller
files, the same god object, and weaker encapsulation than before. Files must
get smaller by state moving, not by braces moving.

No behaviour changes. Nothing the app does is different afterwards.

## Capabilities

### New Capabilities
- `source-file-size`: the ceiling on how long a source file may be, the
  recorded list of what is already over it, and the check that keeps both true.

### Modified Capabilities
- `screenshots`: a driving verb is declared beside what it drives, rather than
  wherever the flag that reaches it happens to arrive.

## Impact

- `Sources/AbydosApp/MainWindowController.swift`: 13,030 lines to about 1,000.
- New collaborators under `Sources/AbydosApp/Run`, `Titlebar`, `Navigator`,
  `Panel` and a new `Results`; none over 1,000 lines.
- `Sources/AbydosApp/AppDelegate.swift` and `LaunchOptions.swift`: the flag
  dispatch reaches a collaborator rather than the window controller.
- `Scripts/` gains the size check; `make warnings` runs it, being the verb that
  already exists to say what is wrong with the repository rather than with a
  build.
- The other files over the ceiling — `BottomPanel` (5,278), `EditorViewController`
  (4,351), `ProjectNavigatorViewController` (4,051), `CodeView` (3,941),
  `LanguageService` (3,606), `TerminalView` (3,470), `AppDelegate` (3,332) — are
  named on the recorded list and left for changes of their own. They are large
  for ordinary reasons, not this one: 42, 39 and 23 driving verbs against this
  file's 193.
