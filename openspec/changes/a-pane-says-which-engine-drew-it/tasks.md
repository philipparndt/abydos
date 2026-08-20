## 1. Deciding where

- [ ] 1.1 Choose between the pane's own furniture, the tab's tooltip, and
      Running Servers and Containers, favouring the non-default engine over a
      mark on everything. Write down what lost and why.
- [ ] 1.2 Check what the tab strip already carries before adding to it: a name,
      a running wash, a Claude badge and a close cross.

## 2. What it says

- [ ] 2.1 A pane says which engine drew it, read from the instance through
      `engineNameForTesting` and never from the setting.
- [ ] 2.2 A pane built before the setting changed says the engine it actually
      has.
- [ ] 2.3 The default engine says nothing, so the mark means "not the usual one".

## 3. The fallback

- [ ] 3.1 A libghostty-vt that will not initialise is heard once, in words that
      say what was asked for and what happened.
- [ ] 3.2 It is not the same mechanism as the mark: one is a moment, the other a
      state.
- [ ] 3.3 Driven with the library made unavailable, so the fallback path is
      exercised rather than reasoned about.

## 4. The declared gaps

- [ ] 4.1 The engine's three declared gaps — OSC 440, `modifyOtherKeys`, tmux's
      prompt row — are readable by somebody who turned the engine on, rather than
      only in a source file.
- [ ] 4.2 If that turns out to want a different shape, say so here and leave it.

## 5. Watched

- [ ] 5.1 Against a scratchpad copy, never a real checkout: the setting off, and
      a pane saying nothing.
- [ ] 5.2 The setting on, a new pane, and the mark.
- [ ] 5.3 A pane opened before the setting changed, beside one opened after.

## 6. Finish

- [ ] 6.1 `.abydos/backlog/spec/terminal.md` says a pane can be asked which
      engine drew it. Name any sentence this makes untrue.
- [ ] 6.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 6.3 Write down what was ruled out on the way.
