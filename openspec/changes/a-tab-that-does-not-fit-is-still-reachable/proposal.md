## Why

Open a dozen terminals and the tabs past the edge of the window are gone. Not
truncated, not scrolled off with a way back — **gone**, because both tab strips
lay their tabs out left to right at whatever width each name needs and neither
stops at the trailing edge:

    Sources/AbydosApp/Panel/BottomPanel.swift   recomputeLayout()  — x += width, no bound
    Sources/AbydosApp/Editor/EditorTabBar.swift recomputeFrames()  — x += width, no bound

Neither takes a `scrollWheel`, so there is nothing to scroll. The panel's own
controls — the session tag, follow, maximise, hide — are placed backwards from
`bounds.width`, so what the reported screenshot shows is tabs and controls drawn
through each other at the right-hand end, both legible and neither usable.

**And for panel tabs there is no keyboard route either.** ⌘] and ⌘[ are
`MainWindowController.selectNextTab`, which is `editor.selectNextTab` — the
editor's tabs and nothing else. A terminal that has run off the end can be
reached by widening the window or by closing the tabs in front of it, and that is
the whole list.

The immediate overlap has a fix in hand: the trailing controls now draw on an
opaque ground, the answer `EditorTabBar.drawPreviewControl` already gave for
itself — *"tabs are free to run underneath; the control stays on top and
reachable, which matters more than a tab's last few characters."* That stops two
things being drawn through each other and it makes this worse rather than better:
a tab that is cleanly hidden is a tab nobody can even see to complain about. The
overlap was the symptom; **no way to reach the tab is the fault**, and it wants
its own answer.

From a direct report with a screenshot of the terminal strip, sixteen tabs deep,
after the same person had reported the overlap. Nearest neighbours: 0522 (never
drive the app against a real checkout, which is how this gets driven) and the
`--tab-fill` verb added while looking at the overlap — twelve tabs was a thing
somebody had to make by hand, twelve clicks at a time, which is why no screenshot
ever showed it.

## What Changes

- **A chevron at the trailing end of a strip that has more tabs than room**,
  listing every tab that is not fully visible and selecting the one chosen. The
  shape already exists twice in this window — the `+`'s chevron on the panel
  strip, the play button's on the run control — and it is the same gesture: the
  control does the ordinary thing and the chevron beside it reaches what is not
  on screen.
- **The count comes with it**, because "3 more" and "11 more" are different
  situations and the chevron alone says neither.
- **Both strips**, not just the terminal one. `EditorTabBar` has the same
  unbounded layout and the same overdrawn control; it is less often hit because
  ⌘] and ⌘[ exist and because editor tabs cap at 260 points and floor at 90,
  where a panel tab has a floor of 96 and no ceiling at all.
- **The active tab is always fully visible.** Selecting a tab from the menu that
  then stays hidden behind the controls is the same fault with an extra click in
  front of it.
- **The menu says which tabs are hidden, not all of them.** A list of everything
  is a tab switcher, which is a different feature with a different gesture
  (⌘⇧O-shaped), and offering it here would put the tab somebody is already
  looking at in a menu of things they cannot see.
- **Not proposed: scrolling the strip.** See `design.md` — it was weighed and it
  loses on this window's geometry.

## Capabilities

### New Capabilities

- `tab-overflow`: what a tab strip does when it has more tabs than width — how
  many are hidden, how they are reached, and what "hidden" means once the
  trailing controls draw over the strip.

### Modified Capabilities

<!-- None in openspec/specs/ that this changes. The sentences it touches are in
     .abydos/backlog/spec/terminal.md — the panel's tab strip — which today says
     nothing about a strip that runs out of room. -->

## Impact

- `Sources/AbydosApp/Panel/BottomPanel.swift` — `PanelTabStrip.recomputeLayout`,
  `draw(_:)`, `mouseDown`, and the trailing-control frames the overflow chevron
  has to sit beside without colliding with them the way the tabs did.
- `Sources/AbydosApp/Editor/EditorTabBar.swift` — `recomputeFrames`,
  `drawPreviewControl`'s neighbourhood, and the same chevron.
- One implementation of "which of these frames are cut off, and by what", used by
  both. The two strips already measure tabs differently on purpose — different
  floors, different ceilings, one with badges — and this is the part that does not
  differ.
- `Sources/AbydosApp/LaunchOptions.swift`, `AppDelegate.swift` — `--tab-fill`
  exists now and is how this is driven; the report it prints wants the hidden
  count in it.
- `.abydos/backlog/spec/terminal.md`, and `editor.md` if the editor strip's
  behaviour is worth a sentence there too.
- No new dependency. A menu is `NSMenu`, which both strips already build.
