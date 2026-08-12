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

## Estimate

2026-08-12 13:50 — about two hours left

## Where the work is

The fork's branch is **`abydos/o-and-collapsed-icons`**, made off
`abydos/openscad-command` so that branch's three unreviewed commits are underneath
this one and a single review and a single tag serve both. It is worked in a git
worktree at `/Users/philipparndt/dev/gostl-0481`, because `~/dev/3d/gostl` is the
user's own checkout and is not to be disturbed.

## Steps

- [ ] Count `openWithGo3mf` entries per press and `OpenWithGo3mf` observers
      registered, embedded and standalone, and say which pair the report is
- [ ] One owner for `o`, with the other made impossible rather than absent
- [ ] A row of icons in the collapsed state, for every section and not only the one
      reported, with an answer for a section too wide for the panel
- [ ] Open-in-go3mf is the one asked about, and it is an icon like the rest
- [ ] Watch both in the embedded viewer, which is where it was reported, against a
      local path override in this worktree's `Package.swift`
- [ ] Take the path override back out, so the branch carries no path only one
      machine has
- [ ] GoSTL's own suite green, and `make warnings` clean here
- [ ] Write down here what was ruled out on the way
- [ ] A branch in `~/dev/3d/gostl` and nothing else — no tag, no push, no repin
- [ ] `spec/<capability>.md` says what the project now does, if the embedded viewer
      is described there at all
