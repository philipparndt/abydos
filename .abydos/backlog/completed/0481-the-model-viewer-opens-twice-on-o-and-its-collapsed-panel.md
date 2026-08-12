# 481. The model viewer opens twice on o, and its collapsed panel offers nothing

> two problems with the gostl integration:
> - there shall be an export button in the collapsed on screen display state
>   (like pressing o)
> - when pressing o the file is opened twice

**Both live in GoSTL and not in this repository**, which is the first thing to
settle before any of it: `Package.swift:100` pins
`https://github.com/philipparndt/gostl.git` at `exact: "0.20.2"`, so nothing here
can consume a fix until that package has a version carrying it. There is already a
branch waiting on the same boundary — `abydos/openscad-command` in `~/dev/3d/gostl`,
three commits, unreviewed and unpushed — so this work joins it rather than starting
a second queue. **Whoever picks this up commits in the fork on a branch and stops:
tagging, pushing and repinning `Package.swift` are the user's calls.**

## Opened twice: two candidate mechanisms, and the reported one decides

`openWithGo3mf` is reachable by two independent paths, and both are live:

- `App/GoSTLApp.swift:587` — a menu `Button("Open with go3mf")` with
  `.keyboardShortcut("o", modifiers: [])`, which posts an `OpenWithGo3mf`
  notification, observed at `App/AppState.swift:389`, which calls
  `openWithGo3mf(sourceFileURL:)`.
- `Input/InputHandler.swift:724` — `case "o":`, which calls
  `openWithGo3mf(sourceFileURL: appState.sourceFileURL)` directly.

One press, two opens. **But the report says "the gostl integration", and inside
Abydos there is no GoSTL menu bar** — a SwiftUI `Commands` menu belongs to a SwiftUI
`App`, and the embedded view is not one. So if the double happens *embedded*, the
menu shortcut cannot be one of the two, and the second path is something else. The
likeliest candidate is the observer: `notificationObservers.append(…)` registers on
setup, and anything that runs that setup twice — a re-created `AppState`, a view
built twice — turns one post into two opens without any second keystroke.

**So establish where it was seen first.** Embedded in Abydos and standalone GoSTL are
different code paths with different answers, and fixing the wrong one leaves the
report standing. Counting how many times `openWithGo3mf` is entered per press, and
how many observers are registered, settles it in one run.

Then one owner. If the menu path survives it should be the only one, because it is
discoverable and shows its own shortcut; if the embedded case has no menu then the
input handler is the only one that can work there and the menu must not double it.
**Say which, and make the other impossible rather than merely absent.**

## Counted, and it is neither of the two candidates

Both configurations were instrumented — a counter on entry to `openWithGo3mf`, a
counter on registration of the `OpenWithGo3mf` observer, a line at each place that
asks for the built file to be opened — and driven with one synthetic `keyDown` for
`o` sent through `NSApp.sendEvent`, so the whole AppKit dispatch was in play. The
built `.3mf` was never really handed to anything: the probe pointed GoSTL at a
`go3mf` shim that logs its argv and honours `--open` by logging, and skipped the
`NSWorkspace` call, so every request to open was counted rather than performed.

Per press, embedded in Abydos and standalone alike:

| | embedded | standalone |
|---|---|---|
| `OpenWithGo3mf` observers registered | 1 | 1 |
| entries into `openWithGo3mf` per press | 1 | 1 |
| requests to open the built `.3mf` | **2** | **2** |

So the pair in this item was the wrong pair. **One press enters `openWithGo3mf`
exactly once; that one entry opens the result twice.** `App/Go3mf.swift` passes
`--open` to `go3mf` *and*, on success, calls `NSWorkspace.shared.open` on the same
file, commented "as a fallback since `--open` may not work reliably when running as
a subprocess with captured stdout/stderr". It works perfectly reliably: go3mf's
`--open` is `exec.Command("open", filepath).Start()`
(`internal/cmd/cmd.go:56`), which was confirmed by putting a logging `open` first on
the `PATH` and running `go3mf build cube.stl -o out.3mf --open` — one `SHIM-OPEN
out.3mf`, every time. Two independent openings, so the slicer is asked twice; on
this machine `.3mf` belongs to BambuStudio, and three BambuStudio processes were
running at the time of the investigation, all three holding the same
`adapter.3mf`.

Two things were ruled out rather than assumed, both by measurement:

- **The observer does not fan out here.** One `AppState`, one observer, embedded and
  standalone. The re-created-`AppState` theory is not what happens — though the
  broadcast *would* fan out with a second window, since every live `AppState`
  answers `OpenWithGo3mf` with its own `sourceFileURL`, and that is a second bug
  the fix below removes rather than leaves.
- **The menu shortcut cannot double the input handler, because the two are
  mutually exclusive.** A menu key equivalent that matches consumes the event, so
  the first responder never sees it; embedded there is no GoSTL menu at all
  (Abydos's own menu bar has six items and none of them are GoSTL's), so the
  input handler is the only path. Both were seen: the synthetic press reached the
  input handler, and one real bare `o` that landed in a standalone run before
  anything had been clicked fired the *menu* path — the observer, once. Never both.

One more thing worth knowing about the embedded viewer, since it decides whether
`o` reaches GoSTL at all: **the viewport is not the first responder when the tab
opens.** It is Abydos's `ModelContainerView`; a click inside the pane makes
`InteractiveMTKView` the first responder, and only then does any single-key
shortcut work. That is what the user does, so it is not a bug — but it is why
`o` appears to do nothing until the model has been clicked once.

## Nothing in the collapsed panel

`UI/MainMenuPanel.swift:84` holds `isExpanded`, defaulting true, and line 106 puts
*all* of `content()` behind it — so collapsing a section leaves a header row and a
chevron and nothing to press. The "Open with go3mf" button and its `KeyHint(key:
"o")` (line 620) go with everything else.

**A row of icons, and the one that was asked about is open-in-go3mf** — asked and
answered, since the report said "export" and `o` opens in go3mf rather than writing a
file through `Model/STLExporter.swift`:

> open in go3mf, and a row of icons

So the collapsed state keeps a compact row rather than one button, which also settles
the rule: no section has to justify *which* of its actions survives collapsing,
because they all do, as icons. Two things that follow and are not decided here — what
each icon is when its expanded row is a word and a `KeyHint`, and what happens when a
section has more icons than the panel is wide. Look at every section rather than only
the one in the report, since the rule now applies to all of them.

## What the folded rows are

One icon per action, the name and the key in the tooltip because the word is gone.
Three decisions, all of them the item's to make:

| section | folded row |
|---|---|
| Info | material (`m`) — the section's only action; the rest of it is readings |
| View | wireframe (`w`), grid (`g`), slicing (`⇧X`), build plate (`⌘B`), plate orientation when a plate is on, home view (`7`), reset view (`ESC`) |
| Tools | distance (`d`), angle (`a`), radius (`r`), triangles (`t`), level (`l`), clear all (`c`) when there are measurements, **open with go3mf (`o`)** |

- **A set of modes is one icon**, because that is already what the keyboard does:
  `w` cycles off/all/edge rather than selecting one, and the open section's radio
  buttons are the same action written out. On is drawn in orange, as the open row
  draws a filled radio button.
- **The six camera presets are left out**, and that is the one place the "every
  action" rule is not followed. They are one action with six arguments; six
  unlabelled directional icons are unreadable where "Front" is not; and the two a
  folded panel is actually for — go home, undo what dragging did — are there. All
  six stay one chevron away. Said rather than quietly dropped.
- **Too wide wraps.** Not scroll and not truncate: the panel is already inside a
  vertical `ScrollView` so another line costs nothing and everything stays
  reachable, a horizontal scroller inside a vertical one is a gesture both of them
  want and hides what it holds behind a swipe nobody knows is there, and truncating
  drops actions, which is the complaint that put the icons there. It is not
  hypothetical either — the panel is only as wide as the pane it floats over, and
  embedded beside an editor that is often less than the 260pt it prefers.
- The set **follows the state**, as the open section's does. Folding Tools halfway
  through a measurement keeps ending and cancelling it rather than going empty at
  the worst moment.

The rows were looked at by rendering `MainMenuPanel` into a bitmap offscreen at
284pt and at 150pt, which is also how the wrapping was checked: three across, two
rows, nothing clipped. That was necessary because **Abydos's own `--screenshot`
cannot photograph the panel** — the model tab composites GoSTL's Metal frame over
the view tree, so the SwiftUI overlays are behind it. Worth knowing before anybody
tries to photograph this pane again.

## Ruled out on the way

- **Both mechanisms this item proposed.** One observer, not several; one entry into
  `openWithGo3mf` per press, not two. Measured in both configurations, numbers
  above. Neither was the bug, and neither can be now: the observer is gone and the
  menu cannot bind a bare key.
- **`Model/STLExporter.swift`.** The report said "export button", and the exporter
  writes an STL to a file. `o` does not go near it; the item settled this before the
  work started and nothing found since disagrees.
- **`--open` being unreliable as a subprocess.** The comment that justified the
  second opening claimed it. A logging `open` put first on the `PATH` sees exactly
  one call for every `go3mf build … --open`, with stdout and stderr both captured.
  The comment was wrong, and it had been believed for as long as it had been there.
- **Photographing the pane with Abydos's `--screenshot`.** The panel never appears:
  the model tab hands GoSTL's Metal frame to the container and it composites over
  the view tree, so every SwiftUI overlay is behind it. Two runs were spent on this.
  What works is `bitmapImageRepForCachingDisplay` on the pane's own view tree —
  AppKit cannot see the Metal layer, so the viewport comes out blank and the
  overlays come out exactly as they are. That is how the folded rows in the embedded
  viewer were looked at.
- **Driving the app from outside.** `osascript` has no assistive access on this
  machine, so System Events cannot type or click, and neither can `CGEvent`. Every
  keystroke and click in this investigation was an `NSEvent` built inside the app
  and sent through `NSApp.sendEvent`, which is the same entry point a real one takes.
  Worth knowing: a synthetic `keyDown` skips AppKit's key-equivalent stage, so it
  always reaches the first responder — which is why the menu path had to be
  established separately rather than by pressing the key.
- **Abydos's `--type`** types into the editor's text view, not into the pane, so it
  cannot reach the viewport at all.

## What is left, and it is not this branch's to do

Nothing here consumes any of it until the package has a version carrying it:
`Package.swift:100` still says `exact: "0.20.2"`, and it was put back exactly as it
was after being pointed at a local path for the watching. Tagging the fork, pushing
it and repinning are the user's calls, and `abydos/openscad-command`'s three commits
are underneath this branch waiting on the same one.

One thing the reviewer should know: **GoSTL's suite has one red that is not this
work's.** `STLParserTests.testInvalidASCIIFormat` — `XCTAssertThrowsError failed:
did not throw an error` — fails identically on `abydos/openscad-command` with none
of these commits applied, checked in a throwaway worktree at that commit. 101 of
102 pass, and this branch touches nothing the parser reads.

## Where the work is

The fork's branch is **`abydos/o-and-collapsed-icons`**, made off
`abydos/openscad-command` so that branch's three unreviewed commits are underneath
this one and a single review and a single tag serve both. It is worked in a git
worktree at `/Users/philipparndt/dev/gostl-0481`, because `~/dev/3d/gostl` is the
user's own checkout and is not to be disturbed.

## Steps

- [x] Count `openWithGo3mf` entries per press and `OpenWithGo3mf` observers
      registered, embedded and standalone, and say which pair the report is
- [x] One place builds the `go3mf` arguments, and it cannot ask go3mf to open the
      result — so the result is opened once, by whoever knows the build finished
- [x] One owner for `o`, with the other made impossible rather than absent
- [x] A row of icons in the collapsed state, for every section and not only the one
      reported, with an answer for a section too wide for the panel
- [x] Open-in-go3mf is the one asked about, and it is an icon like the rest
- [x] Watch both in the embedded viewer, which is where it was reported, against a
      local path override in this worktree's `Package.swift`
- [x] Take the path override back out, so the branch carries no path only one
      machine has
- [x] GoSTL's own suite green, and `make warnings` clean here
- [x] Write down here what was ruled out on the way
- [x] A branch in `~/dev/3d/gostl` and nothing else — no tag, no push, no repin
- [ ] `spec/<capability>.md` says what the project now does, if the embedded viewer
      is described there at all

      **Not done, and not to be done.** There is no capability for the viewer:
      `spec/` names thirteen and none of them describes the model tab. The only
      mention anywhere is `sessions.md`, which uses a `.scad` beside its source as
      an example of a split layout being remembered — a claim about splits, not
      about the viewer. Every behaviour that changed here is inside a dependency
      this repository cannot even consume yet, so a requirement written now would
      describe what Abydos does *not* do until somebody tags GoSTL and repins.
      GoSTL's own living documentation is where it went instead:
      `features/external_tools.feature`, `features/info_panel.feature`,
      `features/menus.feature` and `features/keyboard_shortcuts.feature`, which is
      what that repository's CLAUDE.md asks for.

## Watched in the embedded viewer

Both halves, in a model tab in Abydos built against the branch, with the counting
still in place and the built `.3mf` handed to a logging shim instead of BambuStudio:

- One `keyDown` for `o` → **one** entry into the build, argv
  `["build", "…/cube.stl", "-o", "…/cube.3mf"]` with no `--open`, and **one** open
  request. Before the fix the same press produced two.
- **Clicking the go3mf icon in the folded Tools row** → one entry, one open
  request. So the icon the report asked for works in the place the report was made,
  and not only in a preview.
- A picture of the pane with all three sections folded: `Info` keeps the material
  icon, `View` keeps six, `Tools` keeps six ending in `cube.transparent`.
