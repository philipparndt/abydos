## 1. What the panel knows

- [x] 1.1 `BottomPanel` answers which kinds of pane are in front, as a set —
      one per column, because a split has two and the rail has room to say so.
      Derived from `activeByColumn`, not from `activeSession`, which is the
      focused column's alone.
- [x] 1.2 An empty set when the panel is closed, so the rule "nothing is lit for
      a pane that is not on screen" needs no second path.
- [x] 1.3 A pane kind the rail has no button for contributes nothing rather than
      being mapped to a neighbour: `search`, `usages` and `profiler` have no
      button and must light none.
- [x] 1.4 **Joined, not renamed**, which answers the design's first open
      question. `onActiveTerminalChanged` fires from `refreshTabs()` alone and
      never from `activate` — so a backlog tab coming to the front raised it not
      at all, which is the exact moment the rail needs telling. The new
      `onFrontPanesChanged` is raised from `rebuildColumns()`, the one point all
      eighteen callers come through: activating, closing, splitting,
      unsplitting, restoring.

## 2. What the rail draws

- [x] 2.1 One setter for the bottom group, taking the kinds in front, replacing
      `setTerminalSelected`. It reads like `setSidebarSelection`, which is the
      point: the two groups now keep one rule.
- [x] 2.2 The backlog and review buttons gain selection, which they have never
      had. `backlogButton.isSelected` and `reviewButton.isSelected` are written
      nowhere today.
- [x] 2.3 The debug button is lit for the union — the pane in front, or a session
      running — so nothing is lost with the panel closed.
- [x] 2.4 A running session sets `accent` to `Theme.current.gitAdded`, the green
      the commit button already uses for work not pushed. `StripButton.draw`
      already composes an accent icon with a selection fill; nothing new is
      drawn.
- [x] 2.5 It keeps both, and `updateBottomGroup` is the one place that decides.
      Renamed its stored half to `hasRunningDebugSession`: `isDebugRunning` was
      already taken on the bar by a *question* it asks the window when the debug
      menu is built, and the two are not the same thing.

## 3. Wiring it

- [x] 3.1 `MainWindowController.setPanelVisible` stops calling
      `setTerminalSelected`. **That call is the reported fault**, and leaving it
      beside the new rule would light the terminal over the backlog again.
- [x] 3.2 The window subscribes to the panel's announcement and passes the kinds
      to the rail, the same shape as its existing `setSidebarSelection` call.
- [x] 3.3 The rail is right after every route into a pane, not only the button:
      ⇧⌘B and Agent ▸ Backlog, ⇧⌘R, the debugger starting on its own, a tab
      closed leaving another in front, and the panel being closed.

## 4. Watched

- [x] 4.1 Against a git repository made under the scratchpad, never a real
      checkout. The report, put right:

          RAIL: panel=open backlog=lit review=unlit debug=unlit terminal=unlit
- [x] 4.2 Nothing could read the rail, so `--rail` was added; and nothing could
      *close the panel* either — the app opens a terminal for a project with no
      remembered session, so "the panel is closed" was a state no driven run
      could reach — so `--close-panel` was added beside it. The four:

          closed    panel=closed  backlog=unlit review=unlit debug=unlit terminal=unlit
          backlog   panel=open    backlog=lit
          terminal  panel=open    terminal=lit
          review    panel=open    review=lit

      **The report says why and not only whether**, because two of these four
      buttons can be lit for two reasons and a photograph cannot tell them
      apart.
- [x] 4.3 `--backlog --split-active` puts the backlog beside the terminal that
      was already there, which is the spec's scenario and needed no new verb:

          RAIL: panel=open backlog=lit review=unlit debug=unlit terminal=lit

      And `--split-panes`, a terminal beside the profiler, is the other half of
      the claim: `terminal=lit` with the profiler contributing nothing, so a pane
      with no button lights none.

      **The delay matters and the number is not the rail's fault.** At `--delay
      6` one run read `terminal=lit` alone, because `--split-active` fires at one
      second and the read caught the panel before the move had settled; at
      `--delay 7` it is both lit, three runs out of three. A driver combination
      that needs a moment, not a rail that needs one.
- [x] 4.4 A real delve session on a Go program under the scratchpad — **delve is
      1.27.1 on this machine now and no longer refuses Go 1.27 binaries**, which
      the archived `a-launch-that-failed-says-what-the-adapter-said` was waiting
      for:

          running, panel open    debug=lit+green
          running, panel closed  panel=closed  debug=lit+green
          stopped, pane in front debug=lit
          neither                debug=unlit

      The second is the one that matters: the signal `setDebugRunning` exists for
      survives the panel being shut, and is told apart from the pane merely being
      in front.

## 5. Finishing

- [x] 5.1 **Its pane.** `--review` gives `review=lit`, and the menu the button
      opens lights nothing — which is what the other three do, and the menu is a
      way in rather than a thing on screen.
- [x] 5.2 `make warnings` clean, exit 0 — no warnings in this repository's Swift.
      `make test` exits 2 on the same two `ContainerImageTests` this machine has
      been failing all day: the Apple container runtime's apiserver is not
      running, both report `XPC connection error: Connection invalid`, neither
      touches anything here, and the other 3,177 pass. Recorded in
      `.abydos/today.md`.

No `.abydos/backlog/spec/*.md` file is made untrue: that backlog is gone. What
this adds is `openspec/specs/left-rail/spec.md`, in the delta beside this file.
The `backlog` capability's *The backlog has a button on the left rail* stays true
and untouched — it says the rail carries the button, not what it looks like.
