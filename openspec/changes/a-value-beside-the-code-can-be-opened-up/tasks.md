## 1. A hint that knows what it stands for

- [x] 1.1 `InlineValueSet` carries `[String: Variable]` rather than
      `[String: String]`, so a hint knows its `variablesReference`. The drawn
      text is still `variable.value`, so nothing on screen changes.
- [x] 1.2 `InlineValueHint` says whether it can be opened, from
      `Variable.isExpandable` and nothing else — not the length of the value,
      not a brace in the text.
- [x] 1.3 Tests as claims: `aStructIsOpenableAndAStringIsNot`, and that the
      drawn text is unchanged by any of this.

## 2. Where each hint is on screen

- [x] 2.1 `drawInlineValues` records a rect per hint as it draws, keyed by the
      document line, and throws them away on the next repaint.
      **Nothing is recorded, in the end.** One function — `hintsWithRects` —
      answers where the hints on a row are, and the draw, the cursor, the click
      and the driver all call it. Recording per row would have put bookkeeping
      on the drawing path and left it stale the moment a line was edited; the
      editor font is monospaced, so the same arithmetic answers when somebody
      actually clicks, which is once rather than per repaint.
- [x] 2.2 The rects are arithmetic from the monospaced grid, not a second
      measurement: what is recorded is what the draw already worked out.
- [x] 2.3 Nothing is recorded while nothing is stopped, which is the ordinary
      state.

## 3. The gesture

- [x] 3.1 A click over an openable hint opens it; a click anywhere else in the
      editor does what it does today, including over a hint that cannot be
      opened.
- [x] 3.2 The pointer says so: a cursor over an openable hint, and the hint
      drawn so that it reads as pressable.
- [x] 3.3 Nothing happens when no session is stopped, since there are no hints.

## 4. The window

- [x] 4.1 The variables tree's data source and row drawing come out of
      `DebugPane` into something both it and this can use. `DebugPane` keeps its
      pane; what moves is the tree.
- [x] 4.2 A panel opened at the hint — below the line where there is room, above
      it where there is not, like the completion list.
- [x] 4.3 Escape closes it, a click outside closes it, and the state leaving
      `stopped` closes it.
- [x] 4.4 Expansion inside it fetches children once, through the session.
      **Decided: by reference, and no new session API.** `variables(reference:)`
      was already public and is exactly what an adapter answers a container
      with, so the popup keeps its own small tree and asks by the number the
      adapter gave. `toggleExpansion`, which is keyed by position in `scopes`,
      stays the panel's — a popup opened from a name on a line has no such path
      and should not have to reconstruct one.
      **And once means once**: opening a row and the outline view's own
      `shouldExpandItem` both reach for the same node while `children` is still
      nil, so the adapter was asked twice for one gesture. Counted rather than
      reasoned about — the driven check said three requests where two had been
      asked for — and fixed with a fetching flag.

## 5. Nothing on a drawing path

- [x] 5.1 A test, or a driven run with the adapter's traffic counted, showing
      that scrolling a stopped file makes no `variables` request.
      **Counted**: `children requests after scrolling = 0`, over a file drawn
      row by row with values beside three of its lines. Opening one made it 1,
      and expanding a field inside the window made it 2.
- [x] 5.2 `make timing`, with the load said beside the number: the editor still
      draws fast enough to do while somebody types, stopped, with hints and
      their rects. Exit 0 **at load 34.9 on ten cores** — three and a half per
      core, which is the noisiest reading this project has taken and still
      inside the bounds.

## 6. Watched

- [x] 6.1 Against a scratchpad copy, never a real checkout: `go-service` stopped
      in `main`, `mux` opened, photographed with its fields showing.
- [x] 6.2 A field of `mux` expanded inside the window, showing the lazy fetch
      arriving.
- [x] 6.3 `stage` clicked, and nothing opening.
- [x] 6.4 Resumed with the window up, and the window gone.

## 7. Finish

- [x] 7.1 `.abydos/backlog/spec/debugging.md` says what can be done with a value
      beside the code. Name any sentence this makes untrue.
      **That file no longer exists**: the backlog was dropped between this
      change being written and being applied, and `openspec/specs` is the whole
      account now. The delta carries it, and nothing in the `debug-sessions`
      capability is made untrue — the requirement this adds to says what is
      drawn and how loudly, and says nothing about what can be done with it.
- [x] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 7.3 Write down what was ruled out: a wider hint, a cleverer truncation,
      editing from the popup, and a second copy of the tree.
