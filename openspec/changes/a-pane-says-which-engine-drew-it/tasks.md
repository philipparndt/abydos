## 1. Deciding where

- [x] 1.1 Choose between the pane's own furniture, the tab's tooltip, and
      Running Servers and Containers, favouring the non-default engine over a
      mark on everything. Write down what lost and why.
      **Chosen: the tab, marked and with a tooltip.** The mark is the tab's own
      icon — a filled terminal where the outline one would be — so it costs no
      room in a strip that has none, and the tooltip carries the sentence and
      the declared gaps.
      **Running Servers and Containers lost on shape.** Every row there is a
      process with a pid, an image and a memory figure; an engine is a library
      inside this one, so it would be a row that answers none of the window's
      own questions. It is also somewhere to go, and 0463 is the item that moved
      that answer *out* of such a window and put it beside the file.
      **The tab's tooltip alone lost** because a tooltip nobody hovers is not an
      answer to "how do I see if it is active?" — the mark is what makes it
      askable.
- [x] 1.2 Check what the tab strip already carries before adding to it: a name,
      a running wash, a Claude badge and a close cross.

## 2. What it says

- [x] 2.1 A pane says which engine drew it, read from the instance through
      `engineNameForTesting` and never from the setting.
- [x] 2.2 A pane built before the setting changed says the engine it actually
      has.
- [x] 2.3 The default engine says nothing, so the mark means "not the usual one".

## 3. The fallback

- [x] 3.1 A libghostty-vt that will not initialise is heard once, in words that
      say what was asked for and what happened.
- [x] 3.2 It is not the same mechanism as the mark: one is a moment, the other a
      state.
- [x] 3.3 Driven with the library made unavailable, so the fallback path is
      exercised rather than reasoned about. Through a seam —
      `pretendsTheLibraryWillNotStart` — because whether libghostty-vt loads is
      a fact about this machine, and on one where it loads the branch cannot be
      reached. Setting on, library refusing: `Local: the usual engine`,
      `fallback said: true`. **Set before any window is built**, since the first
      pane is made with the window and a seam set after that is one the pane
      never saw.

## 4. The declared gaps

- [x] 4.1 The engine's three declared gaps — OSC 440, `modifyOtherKeys`, tmux's
      prompt row — are readable by somebody who turned the engine on, rather than
      only in a source file.
- [x] 4.2 If that turns out to want a different shape, say so here and leave it.
      It did not: the three gaps go in the tooltip under *What it cannot do*,
      which is where somebody who turned the engine on is already looking.

## 5. Watched

- [x] 5.1 Against a scratchpad copy, never a real checkout: the setting off, and
      a pane saying nothing. `Local: the usual engine`, nothing marked.
- [x] 5.2 The setting on, a new pane, and the mark.
- [x] 5.3 A pane opened before the setting changed, beside one opened after.
      Driven in one run, the setting flipped between them:

          Local: the usual engine | Local: libghostty-vt, marked

      which is the fact that was indistinguishable before: the setting is on and
      one of these panes is not drawn by it.

## 6. Finish

- [x] 6.1 `.abydos/backlog/spec/terminal.md` says a pane can be asked which
      engine drew it. Name any sentence this makes untrue.
      **That file is gone** — the backlog was dropped between this being written
      and being applied — so the delta goes to the `terminal` capability in
      `openspec/specs`. Nothing there is made untrue: the capability says a pane
      *can* be emulated by libghostty-vt and that an engine says what it cannot
      do, and neither sentence claimed you could tell which was which.
- [x] 6.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 6.3 Write down what was ruled out on the way.
