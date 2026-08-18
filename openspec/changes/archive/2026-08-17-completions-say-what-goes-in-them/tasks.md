## 1. Ask in the right places, and keep what comes back

- [x] 1.1 Add `filterText` to `LSPCompletion` (`LSPMessages.swift`), parsed from the
      item and defaulting to nil. Test with both real shapes: openscad-lsp's
      `{"label": "cube(size, center=false)", "filterText": "cube"}` and
      sourcekit-lsp's `filterText: "withUnsafeCurrentTask(body:)"`.
- [x] 1.2 Match on `filterText ?? label` in `showCompletions`
      (`EditorViewController.swift`), case-insensitive prefix as now.
- [x] 1.3 Read `completionProvider.triggerCharacters` from the stored
      `LSPClient.capabilities` — `renameProvider` at `LSPClient.swift:543` is the
      pattern — and expose it through `LanguageService` for the language of the
      open document.
- [x] 1.4 Ask for the list on a trigger character regardless of prefix length,
      still through the 0.15 s debounce in `scheduleCompletions`. A `.scad` must
      be unchanged: openscad-lsp names no trigger characters.
- [x] 1.5 Stop replacing a preparing server's empty answer with `WordCompletions`.
      `LanguageService.preparing` already holds the fact; the list says the server
      is preparing instead, and `onPreparing(false)` re-asks while the caret is
      still in the same word.
- [x] 1.6 Tests for 1.1–1.5 in `Tests/AbydosKitTests`, named as claims:
      `anItemIsMatchedByItsFilterTextRatherThanItsLabel`,
      `aServerThatNamesNoTriggerCharactersIsAskedOnWordsOnly`,
      `anEmptyAnswerFromAPreparingServerIsNotTheWordsInTheFile`.

## 2. Reduce a server's markdown to something drawable

- [x] 2.1 New reducer in `Sources/AbydosKit/LSP` — no view code — taking the
      flattened string `LSPHover.text(from:)` produces and returning text with
      fences, emphasis runs, HTML tags and `<img>` links gone.
- [x] 2.2 Fixture test using `cube`'s real 1530-character documentation, captured
      from the installed `openscad-lsp`: the parameter description for `size`
      survives, and no ```` ``` ````, `**` or `<` reaches the output.
- [x] 2.3 Decide plain text versus attributed runs for code fences (design, open
      question) and say in the comment which was chosen and what it cost.

## 3. The documentation panel

- [x] 3.1 Carry `documentation` through `CompletionItem.init(_ completion:)`
      (`CompletionPopup.swift:31`), where it is dropped today.
- [x] 3.2 Draw it beside the list, inside the same non-activating child panel, so
      one window is placed and hidden. Bounded height, scrolling past that.
- [x] 3.3 Follow the selection: ↑/↓ change what the panel shows.
- [x] 3.4 No panel at all for an item with no documentation, and no panel where
      there is room on neither side. The list must never move to make room.
- [x] 3.5 `writeImageForTesting` already exists on the popup for exactly this
      reason — extend it so the panel is in the picture, and attach a shot of
      `cube`'s documentation to the item.

## 4. Signature help

- [x] 4.1 Claim `signatureHelp` in `LSPClient.clientCapabilities` with
      `labelOffsetSupport` and `activeParameterSupport`, and add
      `documentationFormat: ["markdown", "plaintext"]` to the completion claim —
      both servers send markdown to a client claiming plaintext today.
- [x] 4.2 `LSPSignatureHelp` in `LSPMessages.swift`: signatures, `activeParameter`,
      and parameter labels in both shapes (a string, and the `[start, end]` offset
      pair sourcekit-lsp sends).
- [x] 4.3 `signatureHelp(uri:position:)` on `LSPClient` and its `LanguageService`
      neighbour, **sent only where `signatureHelpProvider` is in the server's
      capabilities**. openscad-lsp does not answer the request at all, and a
      request nobody answers is a pending continuation until the timeout.
- [x] 4.4 Integration test in the `…LiveTests` style — skipped when the server is
      missing — holding sourcekit-lsp to
      `extruded(height: Double, topEdge: EdgeProfile) -> any Geometry3D` with
      `activeParameter: 1`.

## 5. The hint strip

- [x] 5.1 Tell something outside `CodeView` when a `SnippetSession` starts, moves
      or ends. `index` and `current` are already public; nothing is notified.
- [x] 5.2 Draw the strip above the caret's line — not after the end of the line,
      which `drawInlineDiagnostic` owns. Decide whether it belongs to `CodeView` or
      `EditorViewController` (design, open question) and write down why.
- [x] 5.3 Feed it from signature help where the server has it, drawing the
      `activeParameter` run brighter using the offsets the server sent.
- [x] 5.4 Feed it from the taken completion's documentation where the server has
      no signature help, keyed by the active stop's name — exact match or nothing
      shown.
- [x] 5.5 Test that the hint outlives the completion list, follows Tab between
      stops, and goes when the session does.
- [x] 5.6 Say what it costs. Signature help retriggers on `,` and `:`, so the
      debounce and the "only inside an argument list" condition are the design
      constraint, and the comment names the measurement.

## 6. The snippetSupport claim, measured before it is changed

- [x] 6.1 Drive sourcekit-lsp twice against the same position, once claiming
      `snippetSupport: true` and once `false`, and record what each returns. The
      probes under this change's `design.md` claimed true and got nested closure
      placeholders; what `false` gets is not known.
- [x] 6.2 Flip the claim only if the measurement says it helps, and record the
      answer either way — including "it changes nothing, so the claim was
      cosmetic".

## 7. Finishing

- [x] 7.1 `.abydos/backlog/spec/language-servers.md`: the requirement *"A
      completion is inserted as text, and its stops are stepped through"* gains
      what is *said* while they are stepped through, and the client-capabilities
      prose stops claiming `snippetSupport: false` if 6.2 changed it. Nothing else
      in that file is made untrue by this change.
- [x] 7.2 A `.scad` and a Cadova model both driven by hand, with pictures: `cube`'s
      documentation beside the list, the hint on `size` after the completion is
      taken, and `.` offering `round`/`miter`/`bevel`/`square` in
      `HexKeyHolder/main.swift`. Against a copy under the scratchpad, never a real
      checkout.
- [x] 7.3 `make test` clean.
- [x] 7.4 `make warnings` clean.

## 8. Found while driving it

- [x] 8.1 **A question was being asked about text the server had not been told
      about.** The sync is debounced at 0.4 s and a completion at 0.15, so every
      list was asked for against a document one or two keystrokes stale. Invisible
      while questions were only asked mid-word; asking after a `.` made it plain —
      `Corner.` at the end of a Swift file asked about a position past the end of
      the file the server held, and sourcekit-lsp answered with the whole standard
      library instead of the enum's four cases. `syncTextNow(for:)` sends what is
      waiting first, down the same pipe.
- [x] 8.2 **The hint ran to the end of the page.** A parameter heading is only
      recognisable while it still has its `**` on, so the lookup has to read the
      markdown and not the reduced prose. `CompletionItem` keeps both.
- [x] 8.3 **openscad-lsp writes its parameters two ways.** `cube` puts `**size**`
      on a line of its own; `cylinder` writes `**h** : height of the cylinder or
      cone` on one line. Only the first was read, so `cylinder` got no hint at all
      until it was driven.
