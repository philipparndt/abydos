## 1. A hint that knows what it stands for

- [ ] 1.1 `InlineValueSet` carries `[String: Variable]` rather than
      `[String: String]`, so a hint knows its `variablesReference`. The drawn
      text is still `variable.value`, so nothing on screen changes.
- [ ] 1.2 `InlineValueHint` says whether it can be opened, from
      `Variable.isExpandable` and nothing else — not the length of the value,
      not a brace in the text.
- [ ] 1.3 Tests as claims: `aStructIsOpenableAndAStringIsNot`, and that the
      drawn text is unchanged by any of this.

## 2. Where each hint is on screen

- [ ] 2.1 `drawInlineValues` records a rect per hint as it draws, keyed by the
      document line, and throws them away on the next repaint.
- [ ] 2.2 The rects are arithmetic from the monospaced grid, not a second
      measurement: what is recorded is what the draw already worked out.
- [ ] 2.3 Nothing is recorded while nothing is stopped, which is the ordinary
      state.

## 3. The gesture

- [ ] 3.1 A click over an openable hint opens it; a click anywhere else in the
      editor does what it does today, including over a hint that cannot be
      opened.
- [ ] 3.2 The pointer says so: a cursor over an openable hint, and the hint
      drawn so that it reads as pressable.
- [ ] 3.3 Nothing happens when no session is stopped, since there are no hints.

## 4. The window

- [ ] 4.1 The variables tree's data source and row drawing come out of
      `DebugPane` into something both it and this can use. `DebugPane` keeps its
      pane; what moves is the tree.
- [ ] 4.2 A panel opened at the hint — below the line where there is room, above
      it where there is not, like the completion list.
- [ ] 4.3 Escape closes it, a click outside closes it, and the state leaving
      `stopped` closes it.
- [ ] 4.4 Expansion inside it fetches children once, through the session.
      **Decide and write down** whether the popup resolves its variable to a
      `scopes` path and reuses `toggleExpansion`, or the session grows an
      expansion addressed by reference; the design leaves it open on purpose.

## 5. Nothing on a drawing path

- [ ] 5.1 A test, or a driven run with the adapter's traffic counted, showing
      that scrolling a stopped file makes no `variables` request.
- [ ] 5.2 `make timing`, with the load said beside the number: the editor still
      draws fast enough to do while somebody types, stopped, with hints and
      their rects.

## 6. Watched

- [ ] 6.1 Against a scratchpad copy, never a real checkout: `go-service` stopped
      in `main`, `mux` opened, photographed with its fields showing.
- [ ] 6.2 A field of `mux` expanded inside the window, showing the lazy fetch
      arriving.
- [ ] 6.3 `stage` clicked, and nothing opening.
- [ ] 6.4 Resumed with the window up, and the window gone.

## 7. Finish

- [ ] 7.1 `.abydos/backlog/spec/debugging.md` says what can be done with a value
      beside the code. Name any sentence this makes untrue.
- [ ] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 7.3 Write down what was ruled out: a wider hint, a cleverer truncation,
      editing from the popup, and a second copy of the tree.
