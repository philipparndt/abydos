## Why

**There is no way to open a file by its name.** Not a slow way — none.
`grep -rn "Go to File\|goToFile\|openByName" Sources/` returns nothing, and the
command palette, which is where anybody arriving from another editor will look
first, offers projects, branches, actions and `:` for a line number. A file is
reached by walking the tree to it, or by ⇧⌘F, which searches *contents* — so
finding `GitRepository.swift` means searching for text that happens to be inside
it and reading past every other file that mentions it.

The palette already establishes the gesture. `SwitcherViewController.Scope`
takes VS Code's prefixes on purpose — the comment says "this is the field VS Code
taught people to open and they arrive already knowing what `>` does" — and those
same people arrive knowing that typing a bare file name finds a file. Today that
typing matches project names and branch names and then stops.

The reason this is not simply "walk the tree and filter" is cost, and it is
measurable. On a work tree of 24,691 tracked files:

| source | files | time |
|---|---|---|
| `git ls-files` | 24,691 | **0.03 s** |
| `ProjectSearch.collectFiles()`'s walk, with its exclusions | 25,564 | **3.05 s** |
| the same walk excluding only `.git` | 79,056 | 7.90 s |

The two usable sources agree to within about nine hundred files — the untracked
ones that are not ignored — and git answers a hundred times faster. Three seconds
is not a list you can put behind a keystroke, and 7.9 s is what happens if the
exclusion rules are forgotten.

No originating backlog item: the backlog was dropped on 2026-08-19.

## What Changes

- **Typing a bare word in the command palette lists matching files**, alongside
  the projects and branches it already matches, and choosing one opens it in the
  editor.
- **A file index per project**, built off the main thread and reused between
  openings of the palette, rather than a walk per keystroke.
- **`git ls-files` where there is a repository**, falling back to
  `ProjectSearch.collectFiles()`'s walk where there is not — the walk's exclusion
  rules are already the right ones and are not duplicated.
- **Matching is on the path, ranked by the name.** `GitRepo` finds
  `Sources/AbydosKit/Git/GitRepository.swift`; a match in the last component
  outranks one in a directory above it, so typing a file's name does not bury it
  under everything in a directory of that name.
- The index is **invalidated by the same filesystem events the tree already
  watches**, so a file created a moment ago is findable without reopening the
  project.
- **No new prefix.** Files join the ranked `everything` scope rather than taking
  a sigil of their own: somebody who types `mvnw` should not have to know which
  of four kinds of thing it is before they can type it.

## Capabilities

### New Capabilities

- `palette-file-search`: finding and opening a file by typing part of its path in
  the command palette — where the list of candidate files comes from, what
  ranking puts at the top, when the list is rebuilt, and what the palette shows
  while it is being built for the first time.

### Modified Capabilities

None. The palette is mentioned in `editor` and `version-control` but specified in
neither, so this introduces the capability rather than changing one. ⇧⌘F keeps
its requirements exactly: `search` is about matching the *contents* of files and
is not touched.

## Impact

- `Sources/AbydosApp/Titlebar/ProjectSwitcherPopover.swift` — a `.file` row
  alongside `.project`, `.branch` and `.action`, and its place in the ranking.
- `Sources/AbydosKit/Project/` — the index itself, which belongs in the engine
  and must be testable without a window.
- `Sources/AbydosKit/Search/ProjectSearch.swift` — `collectFiles()` becomes the
  shared fallback rather than search's private helper.
- No new dependency.

Two costs are the whole risk and both have numbers above: building the index must
not touch the main thread, and it must not be rebuilt per keystroke. A palette
that walks 25,564 files while somebody types is the same fault as the project
switch that held the main thread for 2,419 ms, arriving through a different door.
