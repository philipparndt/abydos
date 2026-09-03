## 1. Name it

- [ ] 1.1 A driven verb that double-clicks the title bar and reports the frame and `isZoomed` three times — before, immediately after, and a beat later — since a springback is two frame changes in quick succession and one reading cannot tell them apart.
- [ ] 1.2 Reproduce it on a window restored from the autosave and not touched since, which is what the report says the state is; then on one moved first, which the report says works.
- [ ] 1.3 Write which of the three mechanisms in the design it is into the design — a veto, AppKit's own toggle, or a standard frame too close to the current one. If it cannot be reproduced, say that, and say what was ruled out.

## 2. Fix it

- [ ] 2.1 `windowWillUseStandardFrame` returns the visible frame of the window's own screen.
- [ ] 2.2 Whatever else 1.3 named, and nothing that was not named.
- [ ] 2.3 Check the torn-off terminal windows for the same shape, and record whether the fault was the main window's or every window's.

## 3. Proving it

- [ ] 3.1 Driven: from a restored frame, the double-click leaves the window at the screen's visible frame and still there a beat later; a second one returns it.
- [ ] 3.2 Driven on a window moved first, which is the case the report says already works, so the fix is not read from the one state that was broken.

## 4. Finishing

- [ ] 4.1 Say it in the release notes.
- [ ] 4.2 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `window-frame` spec in this
change is what it makes true.
