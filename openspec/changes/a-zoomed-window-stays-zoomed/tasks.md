## 1. Name it

- [x] 1.1 A driven verb that double-clicks the title bar and reports the frame and `isZoomed` three times — before, immediately after, and a beat later — since a springback is two frame changes in quick succession and one reading cannot tell them apart.
- [x] 1.2 Reproduce it on a window restored from the autosave and not touched since, which is what the report says the state is; then on one moved first, which the report says works.
- [x] 1.3 Write which of the three mechanisms in the design it is into the design — a veto, AppKit's own toggle, or a standard frame too close to the current one. If it cannot be reproduced, say that, and say what was ruled out.

## 2. Fix it

- [ ] 2.1 `windowWillUseStandardFrame` returns the visible frame of the window's own screen. **Tried and reverted, 2026-09-03**: with it in place a zoomed window could not be un-zoomed, reported from the outside within minutes. AppKit's guess was already the visible frame, and taking the decision over broke the `isZoomed` the un-zoom depends on. See the design.
- [x] 2.2 Whatever else 1.3 named, and nothing that was not named. 1.3 named nothing: no fault was found in the app, so nothing was changed.
- [ ] 2.3 Check the torn-off terminal windows for the same shape, and record whether the fault was the main window's or every window's.

## 3. Proving it

- [x] 3.1 Driven: from a restored frame, the double-click leaves the window at the screen's visible frame and still there a beat later; a second one returns it. Proven 2026-09-03 with no behaviour change in the app: 1280×820 → 1920×985, still there a beat later, and a second click back to 1280×820 and still there.
- [ ] 3.2 Driven on a window moved first, which is the case the report says already works, so the fix is not read from the one state that was broken. Inconclusive: in a 900-point window the synthesised click did not reach the title bar — the point lands on one of the app's own titlebar views — so this proves nothing about the app either way. The API path toggles cleanly in that state.

## 4. Finishing

- [x] 4.1 Say it in the release notes. Nothing to say: no behaviour changed. What the release gains is the instrument, which is a driving verb.
- [x] 4.2 `make test` and `make warnings`, both clean, both by their exit codes. Green here on 2026-09-03: 4015 tests in 512 suites, exit 0, load 20.1 over 14 cores; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `window-frame` spec in this
change is what it makes true.
