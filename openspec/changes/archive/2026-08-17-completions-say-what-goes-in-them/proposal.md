## Why

Taking `cube` in a `.scad` leaves `cube(size = size, center = false);` with `size`
selected, and nothing on screen says what `size` is. It is either one number or a
three-value array `[x, y, z]`, and the only way to find that out today is to leave
the editor. **The server already said so and the editor threw it away.**

Driven against the installed `openscad-lsp`, the item it answers `cub` with is:

    {"label": "cube(size, center=false)",
     "filterText": "cube",
     "insertText": "cube(size = ${1:size}, center = false);$0",
     "insertTextFormat": 2, "kind": 9,
     "documentation": {"kind": "markdown", "value": "…1530 characters…"}}

and those 1530 characters contain exactly the missing sentence:

> **parameters**: **size** — single value, cube with all sides this length; 3 value
> array [x,y,z], cube with dimensions x, y and z. **center** — false (default), 1st
> (positive) octant, one corner at (0,0,0); true, cube is centered at (0,0,0)

`LSPCompletion` parses `documentation`. `CompletionItem.init(_:)` in
`CompletionPopup.swift` does not copy it, so it stops there. The row draws `label`
and `detail`, and openscad-lsp sends no `detail` at all — so the popup has one line
of signature and the manual page is discarded on the way to it.

The second report is a different fault with the same result. In
`abydos-examples/cadova-models/Sources/HexKeyHolder/main.swift`, typing `.` where an
enum case belongs — `style: .round`, `topEdge: .chamfer(…)` — offers nothing.
**The editor never asks.** `scheduleCompletions` returns early unless the word
prefix is at least two characters, and `WordMotion.prefix` stops at any non-word
character, so after a `.` the prefix is empty and no request is sent. sourcekit-lsp
advertises `"triggerCharacters": [".", "("]` and nobody reads it.

Asked directly, sourcekit-lsp answers that position with `round`, `miter`, `bevel`,
`square` — `kind: 20`, `detail: "LineJoinStyle"`. But **only after 123 seconds**: at
1 s, 11 s, 32 s and 62 s after the file was opened it answered 0 items with no
error, while it built 651 files to index them. An empty answer from a warming server
is indistinguishable from "this language has no completions", and the editor turns
it into the words already in the file, which looks like an answer and is not.

Both servers were driven from this machine on 2026-08-17; the probes are in the
change's `design.md`. Nearest backlog neighbours: 0501 (a server that is still
preparing, and the empty answers it gives), 0536/0540 (the snippet session this
builds on) and 0538. This came from a direct report rather than an item of its own.

## What Changes

- **The completion list shows what the server said about the selected item.** The
  documentation beside the list, not a line of `detail` under a signature. Markdown
  arrives from both servers today and is rendered or reduced to text — the editor
  currently claims `documentationFormat: ["plaintext"]` and is sent markdown anyway.
- **The parameter under the caret is named while it is being filled in.**
  `textDocument/signatureHelp` where a server has it — sourcekit-lsp answers
  `extruded(height: Double, topEdge: EdgeProfile) -> any Geometry3D` with
  `activeParameter: 1` and byte offsets for each parameter's label. openscad-lsp
  advertises **no** `signatureHelpProvider`, so for a `.scad` the hint is the
  completion item's own documentation, keyed to the snippet stop the session is on.
  Two sources, one thing on screen.
- **The list is asked for on a server's own trigger characters**, not only on the
  second letter of a word. `.` and `(` for sourcekit-lsp, whatever `initialize`
  returned for anything else.
- **Items are matched by `filterText` where a server sends one.** The editor filters
  on `label`, which is `cube(size, center=false)` for openscad-lsp and a whole Swift
  signature for sourcekit-lsp. `cube` matches by luck; `withUnsafeCurrentTask(body:)`
  does not.
- **A server that is not ready yet says so** rather than being replaced by the words
  in the file, and the list refreshes when it becomes ready. `LanguageService` already
  tracks `preparing` (0501) and already refuses to treat an empty answer from a
  preparing server as evidence; the popup does not use either fact.
- **The editor stops claiming `snippetSupport: false`** while expanding snippets.
  It has stepped through stops since 0536, and a server that believes the claim
  sends plain text where it could have sent typed placeholders.

## Capabilities

### New Capabilities

- `completion-detail`: what the list says beyond the word — the documentation a
  server sends for the selected item, where it is drawn, and what is shown when
  there is none.
- `parameter-hints`: what is on screen about the parameter the caret is in, from
  `signatureHelp` where a server has it and from the taken completion's own
  documentation where it does not.
- `completion-triggers`: when the list is asked for, what is matched against, and
  what is shown instead of an answer while a server is still preparing.

### Modified Capabilities

<!-- None in openspec/specs/, which is empty. The sentences these change are in
     .abydos/backlog/spec/language-servers.md — "A completion is inserted as text,
     and its stops are stepped through" grows a companion about what is *said*
     while they are stepped through, and the client capabilities paragraph stops
     claiming snippetSupport: false. -->

## Impact

- `Sources/AbydosApp/Editor/CompletionPopup.swift` — `CompletionItem` drops
  `documentation` today; the popup is a single-column table with no room for it.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — `scheduleCompletions`,
  `showCompletions`, `handleCompletionKey`, and the `onCommit` that starts a
  snippet session.
- `Sources/AbydosApp/Editor/LanguageService.swift` — `completions(url:…)`, the
  `preparing` set, and a new `signatureHelp` neighbour.
- `Sources/AbydosKit/LSP/LSPClient.swift` — `clientCapabilities` (`snippetSupport`,
  `documentationFormat`, a `signatureHelp` claim), a `signatureHelp` request, and
  reading `completionProvider.triggerCharacters` out of the stored `capabilities`.
- `Sources/AbydosKit/LSP/LSPMessages.swift` — `LSPCompletion` gains `filterText`;
  `LSPSignatureHelp` is new.
- `Sources/AbydosKit/LSP/SnippetSession.swift` — the active stop is already public
  (`index`, `current`); what is missing is anything being told when it advances.
- `LanguageService.hover` has no caller in the app today — the only tooltip in the
  editor is the diagnostic one. Whatever draws a server's prose here is the first
  place to put it, and hover is the obvious second.
- `.abydos/backlog/spec/language-servers.md`.
- No new dependency. Markdown is reduced to text with what is already here —
  `LSPHover.text(from:)` does the flattening for hover today.
