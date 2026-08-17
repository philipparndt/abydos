## 1. The measurement, in the engine

- [ ] 1.1 A small type in `Sources/AbydosKit` — no view code — answering, for a
      list of frames and the leading edge of whatever is drawn over the trailing
      end, which are wholly visible and which are hidden before and after.
- [ ] 1.2 Tests as claims: `aTabUnderTheTrailingControlsIsHidden`,
      `aTabThatFitsExactlyIsVisible`, `nothingIsHiddenWhenTheyAllFit`,
      `tabsBeforeTheRunAreCountedToo`.
- [ ] 1.3 The least move that brings one frame wholly into view, and a test that
      it is the least — moving further than needed is a strip that jumps.

## 2. The panel strip

- [ ] 2.1 `PanelTabStrip` lays out from a starting tab rather than always from
      the first, held by identity so a tmux reload cannot shift it.
- [ ] 2.2 The run moves only when the active tab does not fit, and by the least
      that makes it fit. Nothing else moves it.
- [ ] 2.3 An overflow chevron with the count, at the trailing end, inside or in
      front of the controls' opaque ground — decide which and say why (design,
      open question).
- [ ] 2.4 Its menu lists the hidden tabs in tab order, hidden-before first.
      Decide whether a `Local` entry carries its directory (design, open
      question); sixteen identical names is the reported case.
- [ ] 2.5 A strip whose tabs all fit draws no chevron.
- [ ] 2.6 A gone starting tab puts the strip back at the first.

## 3. The editor strip

- [ ] 3.1 The same for `EditorTabBar`, over its own measurement — it caps at 260
      and floors at 90 where the panel floors at 96 with no cap, and those stay
      different.
- [ ] 3.2 Decide whether it shows the count or only the chevron (design, open
      question); it has ⌘] and ⌘[, so its case is milder.

## 4. Driving it

- [ ] 4.1 `--tab-fill` prints the hidden count beside the pane count, so a driven
      run asserts on a number rather than on a picture.
- [ ] 4.2 A driver verb that opens the overflow menu and prints its entries.
- [ ] 4.3 Driven against a scratchpad copy, never a real checkout: a full strip,
      the count, the menu, a hidden tab chosen and then visible, and the run
      moving by the least that fits. Pictures for the change.

## 5. Finishing

- [ ] 5.1 `.abydos/backlog/spec/terminal.md` gains what a strip does when it runs
      out of room; `editor.md` too if 3.2 gives the editor strip a behaviour
      worth stating. Say which sentences, if any, this makes untrue.
- [ ] 5.2 `make test` clean.
- [ ] 5.3 `make warnings` clean.
