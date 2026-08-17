## 1. The measurement, in the engine

- [x] 1.1 A small type in `Sources/AbydosKit` — no view code — answering, for a
      list of frames and the leading edge of whatever is drawn over the trailing
      end, which are wholly visible and which are hidden before and after.
- [x] 1.2 Tests as claims: `aTabUnderTheTrailingControlsIsHidden`,
      `aTabThatFitsExactlyIsVisible`, `nothingIsHiddenWhenTheyAllFit`,
      `tabsBeforeTheRunAreCountedToo`.
- [x] 1.3 The least move that brings one frame wholly into view, and a test that
      it is the least — moving further than needed is a strip that jumps.

## 2. The panel strip

- [x] 2.1 `PanelTabStrip` lays out from a starting tab rather than always from
      the first, held by identity so a tmux reload cannot shift it.
- [x] 2.2 The run moves only when the active tab does not fit, and by the least
      that makes it fit. Nothing else moves it.
- [x] 2.3 An overflow chevron with the count, at the trailing end, inside or in
      front of the controls' opaque ground — decide which and say why (design,
      open question).
- [x] 2.4 Its menu lists the hidden tabs in tab order, hidden-before first.
      Decide whether a `Local` entry carries its directory (design, open
      question); sixteen identical names is the reported case.
- [x] 2.5 A strip whose tabs all fit draws no chevron.
- [x] 2.6 A gone starting tab puts the strip back at the first.

## 3. The editor strip

- [x] 3.1 The same for `EditorTabBar`, over its own measurement — it caps at 260
      and floors at 90 where the panel floors at 96 with no cap, and those stay
      different.
- [x] 3.2 Decide whether it shows the count or only the chevron (design, open
      question); it has ⌘] and ⌘[, so its case is milder.

## 4. Driving it

- [x] 4.1 `--tab-fill` prints the hidden count beside the pane count, so a driven
      run asserts on a number rather than on a picture.
- [x] 4.2 A driver verb that opens the overflow menu and prints its entries.
- [x] 4.3 Driven against a scratchpad copy, never a real checkout: a full strip,
      the count, the menu, a hidden tab chosen and then visible, and the run
      moving by the least that fits. Pictures for the change.

## 5. Finishing

- [x] 5.1 `.abydos/backlog/spec/terminal.md` gains what a strip does when it runs
      out of room; `editor.md` too if 3.2 gives the editor strip a behaviour
      worth stating. Say which sentences, if any, this makes untrue.
- [x] 5.2 `make test` clean.
- [x] 5.3 `make warnings` clean.

## 6. What the decisions came out as

- [x] 6.1 **The chevron sits in front of the controls' ground, with its own**
      (2.3): it is part of the tab strip — it counts tabs and lists tabs — and
      putting it inside the panel's controls would have grouped it with hide and
      maximise, which are about the panel rather than about what is in it.
- [x] 6.2 **A hidden entry carries a number and its name** (2.4). The report is
      sixteen tabs called `Local`, so the name alone is no more use than no menu;
      tmux's own number where there is one, since that is what `C-b 2` selects,
      and the position along the strip otherwise. The editor's menu carries the
      subtitle instead — files of the same name in different directories are what
      fills a tab bar.
- [x] 6.3 **The editor strip shows the count too** (3.2). Its case is milder,
      but two strips answering the same question two ways is what this change
      exists to stop.
- [x] 6.4 `--tab-fill` prints the hidden count and then chooses a hidden tab, so
      the half a still picture cannot show — the run moving the least that brings
      it into view — is in the driver's output.
