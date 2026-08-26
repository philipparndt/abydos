## Context

`MainWindowController` is 13,030 lines. The proposal has the measurements; this
is about where the cuts go and in what order, and about the two AppKit facts
that decide the shape.

The clusters in the proposal were found by asking what each of the 674 members
actually touches, not by reading the section headings — the headings are no
longer true, which is why the file needed measuring rather than skimming.
Clustered that way, and with the driving verbs set aside, the file is:

| | lines | members |
|---|---|---|
| driving verbs that forward and nothing else | 2,204 | 89 |
| driving verbs that read one cluster's state | 1,070 | 83 |
| running, in all its forms | ~2,500 | 74 |
| the window itself: layout, loading, following the terminal, menu actions | 3,108 | 236 |
| the sidebar tools | ~930 | 55 |
| the titlebar and its pills | ~760 | 35 |
| debugging | ~800 | 37 |
| usages, search, rename, copy a link | ~400 | 21 |

The two AppKit facts:

**A menu item's target is the responder chain.** 108 `@objc` actions live on
this class and `validateMenuItem` is one long switch over their selectors. An
action moved to an object that is not in the chain is not found, and the menu
item goes grey with nothing to say why. This is the constraint that stops the
obvious plan — move each action to the object that does the work — from being
correct on its own.

**`private` is file-scoped in Swift.** A member marked `private` is visible in
the declaring file and in extensions of that type *in that same file*. Splitting
the class across files therefore costs exactly as much encapsulation as the
number of properties the other files need.

## Goals / Non-Goals

**Goals:**

- No file in `Sources` over 1,000 lines, `MainWindowController` included, and a
  check that keeps it that way as the other twenty-six are worked down.
- State moves out of the window controller's scope, so that a cluster's fields
  are reachable only by the code that owns them.
- The driving surface stops being the reason state cannot be private.
- Every step is a commit that builds, passes `make test` and `make warnings`,
  and changes nothing anybody can observe.

**Non-Goals:**

- Any behaviour change. Every launch flag, menu item and shortcut does exactly
  what it did.
- The other twenty-six files over the ceiling. They go on the recorded list and
  get changes of their own; `BottomPanel` at 5,278 lines is the obvious next
  one and it is not this one.
- Faster builds. Measured and disproved in the proposal — `AbydosApp` is
  whole-module, so file size does not enter into it.
- Moving anything into `AbydosKit`. These are view controllers and they stay in
  the app target.

## Decisions

### Collaborators own state; extensions do not

The unit of extraction is a type that owns fields, not an `extension
MainWindowController` in a new file. Extensions across files would force all
131 properties to `internal` — the same god object with smaller files and less
encapsulation than it started with, which is a worse position than 13,030 lines
because it looks solved.

The precedent is already here: `EditorAreaController` is a façade the window
talks to, owning its own subtree, and it does not know a window controller
exists — the window hands it callbacks (`onTearOffTab`, `onBecameEmpty`) and
reads back what it needs. Every collaborator below is built the same way.

*Alternative considered:* a single `WindowModel` holding the state with the
controller as a thin view layer. Rejected — it is one god object wearing
another's name, and the clusters measured above barely overlap, so there is
nothing for a shared model to be shared between.

### A collaborator is handed what it needs, never the window

`RunCoordinator` takes the bottom panel and the project root. It does not take
`MainWindowController`. An `unowned let window: MainWindowController` would
make every collaborator a route back into everything, and after five of them
the coupling is worse than one class — a cycle rather than a tree, and no way
to test any piece of it.

Where a collaborator must tell the window something, it does so through a
closure the window sets, as `EditorAreaController` already does.

### The `@objc` actions stay on the window controller, as forwards

Being the responder is part of what a window controller is for, so the 108
actions and `validateMenuItem` stay where AppKit looks for them and become one
line each:

```swift
@objc func runSelected(_ sender: Any?) { run.runSelected() }
```

The exception is a collaborator that is already an `NSViewController` in the
view hierarchy — the sidebar and the editor area — because a view controller is
in the responder chain by construction. Its actions go on it and are found
without splicing.

*Alternative considered:* splicing non-view collaborators into
`nextResponder`. Rejected for the ones that are not views: hand-built responder
chains break in ways that are invisible until a menu item is grey, and a
one-line forward has no such failure mode.

### `MainWindowController` may span files, once its state has gone

The forwarding actions and the window-delegate conformances are the last things
to move, and by then the class holds a handful of `let` collaborators and its
own layout fields. At that point splitting *is* allowed — the collaborators
become `private(set)` at internal visibility, which is six or seven names, not
131. What the rule forbids is reaching for extensions *instead of* moving
state, not extensions as such.

Concretely, the file becomes:

- `MainWindowController.swift` — the window, the collaborators, loading a
  project, the split layout
- `MainWindowController+MenuActions.swift` — the 108 forwards and
  `validateMenuItem`
- `MainWindowController+Layout.swift` — `NSSplitViewDelegate`, panel geometry

`NSToolbarDelegate` does not stay: a toolbar's delegate may be any object, so
those 386 lines go to `TitlebarController` whole and are set as the toolbar's
delegate directly.

### The driving verbs move first, and to the type they forward to

2,204 lines forward to a sub-controller and touch nothing else.
`editorTextForTesting` goes on the editor, `breakpointReportForTesting` on the
debugger's pane. `LaunchOptions` dispatch reaches the sub-controller through
the window's existing accessor.

This goes first for three reasons: it is mechanical, it changes no behaviour at
all, and it is 28% of the file — after it the sections describe their contents
again, which is what makes the harder cuts reviewable. The remaining 1,070
lines of driving verbs read one cluster's state each and travel with that
cluster, as the `screenshots` delta requires.

### The ratchet is a recorded list, checked by `make warnings`

`Scripts/file-size.sh`, run from `warnings.sh`, walks `Sources` for `.swift`
files and compares each against `Scripts/file-size-allowed.txt` — one line per
file, `<lines> <path>`, sorted, twenty-seven entries on the first day.

- not listed and over 1,000 → fail
- listed and longer than recorded → fail, printing both numbers
- listed and under 1,000 → say it may be struck from the list
- shorter but still over → pass silently; tightening the number is a choice
  somebody makes, so that a refactor is not obliged to also edit a manifest

Every fault is printed, sorted by excess, before it exits non-zero. Stopping at
the first would turn one 67-second run into as many runs as there are faults.

*Alternative considered:* failing on everything over the ceiling from day one.
Rejected — 27 files and 44,296 lines of excess means the check is switched off
the same afternoon, and a check that was switched off teaches that the checks
here are advisory. That lesson is more expensive than the file.

*Alternative considered:* SwiftLint's `file_length`. Rejected — a new
dependency needs a written reason, and this is fifteen lines of shell against a
tool with its own configuration surface and its own opinions.

## Risks / Trade-offs

**A menu item goes grey and nobody notices.** → The forwards are mechanical and
one line; the risk is a missed one. `reportToolbarForTesting` and the existing
menu driving verbs cover part of it, and each commit that moves actions runs
the driven flags that reach them. Where an action has no driven coverage, the
forward is written but the action is not moved off the class.

**A refactor with no observable change is unreviewable in one commit.** → One
collaborator per commit, each green on `make test` and `make warnings`. The run
cluster is several commits, not one.

**Moving driving verbs quietly widens `private` instead of moving state.** →
Forbidden by the `screenshots` delta, and visible in review as a `private`
disappearing. The collaborators are internal; their fields are not.

**A commit lands the file under 1,000 by cutting where it is easy rather than
where the seam is.** → The seams are the measured clusters, and the ratchet
accepts a shorter file without asking how, so there is no pressure to hit a
number in a hurry. The check is a floor under the work, not the work's goal.

**`ProjectSessions` restores per-project layout, and it reads state that is
moving.** → Session save and restore is exercised by the driven project-switch
verbs; those run on every commit that touches a cluster with restored state.

## Migration Plan

Each step is a commit, green, and observably identical.

1. `Scripts/file-size.sh`, the recorded list at today's twenty-seven, wired
   into `make warnings`. The check exists before the work it measures.
2. The 2,204 lines of forwarding driving verbs, to their sub-controllers.
3. `ResultsPresenter` — usages, search, rename, copy a link. Smallest, most
   self-contained, and the one that proves the pattern.
4. `TitlebarController` — pills, worktrees, the devcontainer, and
   `NSToolbarDelegate`.
5. `SidebarController` — the tool strip, the five panes, the popover, the git
   log and commit pages. An `NSViewController`, so its actions go with it.
6. `DebugCoordinator` — breakpoints, the execution marker, going to a place.
7. The run cluster, as several commits: discovery, then starting, then the
   configuration menu and editor, then hot code replace, then the cluster and
   DevPod.
8. `MainWindowController` splits into its three files, and the recorded list
   loses its first entry.

Rollback is per commit; nothing here is a migration of anybody's data or
settings.

## Open Questions

- Whether `SidebarController` should be one `NSViewController` or a host plus
  the five panes it already has. Deferred to step 5, when the 930 lines are in
  front of somebody rather than counted from outside.
- Whether `Tests` should be under the ceiling too. Three test files are over it
  and a test file is read differently — it is a list of claims, not a machine.
  Left out of the check for now; the requirement names `Sources` only.
- Whether the run cluster wants one `RunCoordinator` with helpers or several
  peers. The 2,500 lines will not fit in one file under the ceiling either way,
  so this is about which one the window holds, and it can be answered at step 7.
