## Context

Three things stand between a server's answer and the screen, and each is a
separate fault.

**The documentation never leaves the parser.** `LSPCompletion` reads
`documentation` (`LSPMessages.swift:307`, flattened by `LSPHover.text(from:)`),
and `CompletionItem.init(_ completion:)` in `CompletionPopup.swift:31` copies
`label`, `insertText`, `detail` and `isSnippet` — not `documentation`. The row
view draws the label and, beside it, `detail`. openscad-lsp sends no `detail`,
so the row is the label alone.

**The list is only ever asked for on a word.** `scheduleCompletions` returns
early below two characters, and `WordMotion.prefix` walks back over `.word`
characters only, so a `.` yields `""`. Nothing reads `completionProvider`
out of the capabilities the client already stores (`LSPClient.capabilities:109`,
read today only for `renameProvider`).

**An empty answer is dressed up as a full one.** `showCompletions` falls through
to `WordCompletions.candidates(…)` whenever the server said nothing — which is
also what a server that is still preparing says. `LanguageService` knows the
difference: `preparing` (0501) is maintained from `LSPClient.onPreparing`, and
`answered(withContent:)` already refuses to hold an empty answer against a
preparing server. The popup is told none of it.

### What the two servers actually send

Both were driven from this machine on 2026-08-17, over stdio, with a client
claiming `snippetSupport: true` and `documentationFormat: ["markdown"]`.

`openscad-lsp` (cargo, `--stdio`), `initialize` result:

    completionProvider: {}          ← no triggerCharacters
    hoverProvider: true
    renameProvider: {prepareProvider: true}
    …and no signatureHelpProvider at all

Its answer to `cub` is 82 items whose labels are whole signatures —
`cube(size, center=false)`, `cylinder(h, r, center=false)` — with `filterText:
"cube"`, `insertTextFormat: 2`, and 1530 characters of markdown documentation
carrying the parameter table. Hovering an existing `cube` returns the same prose.
`textDocument/signatureHelp` is not answered at all: the request went out and no
reply ever came back, which is worse than an error and is what the probe's first
run hung on.

`sourcekit-lsp` (Swift 6.3), `initialize` result:

    completionProvider: {resolveProvider: true, triggerCharacters: [".", "("]}
    signatureHelpProvider: {triggerCharacters: ["(", "["],
                            retriggerCharacters: [",", ":"]}

Against `HexKeyHolder/main.swift`, at `style: .` with the identifier removed:

| time after open | items |
| --- | --- |
| 1.1 s | 0 |
| 11.1 s | 0 |
| 32.1 s | 0 |
| 62.2 s | 0 |
| 122.8 s | 7 — `round`, `miter`, `bevel`, `square` (`kind: 20`, `detail: "LineJoinStyle"`), then `encode`, `hash` |

The gap is an index build of 651 files, announced the whole way through
`$/progress` (`Preparing Clipper2`, `Preparing oneTBB`, …). None of the empty
answers was an error. Once warm, `signatureHelp` inside `.extruded(height:
height, ` answers:

    label: "extruded(height: Double, topEdge: EdgeProfile) -> any Geometry3D"
    activeParameter: 1
    parameters: [{label: [9, 23]}, {label: [25, 45]}]

Its completion labels are whole signatures too — `withUnsafeCurrentTask(body:
(UnsafeCurrentTask?) throws -> T) rethrows` with `filterText:
"withUnsafeCurrentTask(body:)"` — so the editor's `label.hasPrefix(prefix)`
filter throws away items the server intended to match.

### What is already here to build on

- `SnippetSession` knows which stop is active (`index`, `current`) and follows
  edits. Nothing outside `CodeView` is told when it advances.
- `LSPHover.text(from:)` flattens `MarkupContent`, arrays and the deprecated
  `MarkedString` into one string. It does **not** touch markdown syntax.
- `drawInlineDiagnostic` puts dimmed text after the end of the line — the
  Error Lens arrangement, and the precedent for saying something beside code
  without a window.
- `LanguageServerFooter` says which server is running and what state it is in.
- `LanguageService.hover` exists and nothing in the app calls it.

## Goals / Non-Goals

**Goals:**

- The type a parameter takes is readable without leaving the editor, in both a
  `.scad` and a Swift file, from what the server already says.
- The list is offered where an enum case belongs, and matched the way the server
  asked for.
- "The server is not ready" and "there is nothing here" stop looking the same.
- One thing on screen for "what goes here", fed by two sources, so a language
  without `signatureHelp` is not a second feature with a second look.

**Non-Goals:**

- Hover. `LanguageService.hover` having no caller is a real gap and a separate
  item; this change should leave whatever it builds reusable by it, not do it.
- `completionItem/resolve`. sourcekit-lsp advertises `resolveProvider: true`,
  but both servers already send full documentation in the first answer, so
  resolving is a second round trip for something already in hand. Revisit if a
  server turns up that sends only labels.
- Fuzzy matching and ranking. `sortText` is parsed and unused, and ordering is
  its own argument.
- Rendering markdown properly — headings, tables, images. See below: the
  documentation openscad-lsp sends contains HTML tables and remote `<img>` tags,
  and none of that is going on screen as markup here.

## Decisions

**Where the documentation is drawn: a panel beside the list, not a second line
in the row.** 1530 characters do not fit in a 22-point row, and truncating them
loses the parameter table, which is the whole point. Ruled out:

- *A wider row with the doc as `detail`.* The popup already caps at 460 points
  and elides; this is the current design failing, made bigger.
- *The `toolTip` used for diagnostics.* A tooltip needs the pointer to rest on
  something, and the completion list is driven entirely by keys — the item whose
  documentation is wanted is the *selected* one, which the pointer is nowhere
  near.
- *A separate window that steals focus.* The popup is deliberately a
  non-activating child panel so the caret keeps blinking; the doc panel is a
  second child of the same kind, or a second view inside the same one. Second
  view inside the same panel is preferred — one window to place, one to hide,
  and no chance of the two separating when the popup is repositioned near a
  screen edge.

**The markdown is reduced to text, in AbydosKit, by something with tests.**
`LSPHover.text(from:)` unwraps the envelope and stops there, so the panel would
otherwise show ```` ```scad ```` fences, `**parameters**` and this, verbatim:

    <a href="https://en.wikibooks.org/wiki/File:OpenSCAD_…"><img
    src=https://upload.wikimedia.org/…/220px-…jpg width=176.0 height=151.2/></a>

Ruled out: `NSAttributedString(markdown:)` — it is Foundation, it is free, and
it does nothing about the HTML, which is the half that would look broken. A
reducer in `Sources/AbydosKit/LSP` can be tested without a window, which is
where the line in this repository is. **Open:** whether fenced code keeps the
editor font as an attributed run, or whether the first pass is plain text
throughout. Plain text first is cheaper to get right and the parameter table
survives either way.

**How much of it is shown.** The panel is bounded — a few hundred points of
height, scrolling if there is more — rather than sized to the content, because
the content is a wiki page. **Open:** whether the reducer should prefer the
`**parameters**` section when it can find one. That would put the answer to the
reported question first for every OpenSCAD builtin, and it is a heuristic about
one server's prose, which is the kind of thing that rots. Leaning: no
special-casing in the first pass; look at the panel with real content before
deciding.

**The parameter hint is a floating strip above the caret's line.** It has to
survive the completion being taken — the moment `size` is selected and the
question "what is `size`" is being asked is the moment the list closes. Ruled
out:

- *In the documentation panel only.* Closes with the list, so it misses exactly
  the moment that motivated the change.
- *After the end of the line, like `drawInlineDiagnostic`.* Attractive because
  the precedent is here and it reads without aiming, but it is the same strip of
  screen the inline diagnostic uses, and a half-typed call is precisely when
  there is a diagnostic on that line. Two dimmed messages fighting for one place
  is a worse bug than the one being fixed.

**Two sources, one strip.** Where the server advertises `signatureHelpProvider`,
the strip is `textDocument/signatureHelp`: label, with the `activeParameter`
run drawn brighter using the offsets the server sends. Where it does not —
OpenSCAD — the strip is the taken completion's own documentation, kept for the
life of the snippet session, and the active stop names which parameter to show:
the stop's default text in `cube(size = ${1:size}, …)` is `size`, which is the
heading in the prose. **The name match is exact or nothing is shown.** Guessing
which paragraph is meant would put the wrong type under the caret, and a wrong
answer here is worse than none.

**Triggers come from the server, not from a list in the editor.**
`completionProvider.triggerCharacters` out of the stored capabilities. The
two-character rule stays for ordinary words — it is what stops a request per
keystroke — but a trigger character asks immediately, through the same 0.15 s
debounce. openscad-lsp sends no trigger characters, so a `.scad` behaves exactly
as it does today.

**Matching is `filterText ?? label`, prefix, case-insensitively.** The smallest
change that stops throwing away items, and it is what both servers are asking
for. Fuzzy matching is a separate argument and `sortText` is already sitting
unused; not opened here.

**A preparing server is said, not silently replaced.** While
`LanguageService.preparing` holds the key, an empty answer does not fall through
to the words in the file — the list says the server is still preparing, and the
existing `onPreparing(false)` callback is what re-asks. Ruled out: polling, and
a timeout-and-retry. The signal is already there and already plumbed to a chip
in the footer; a second mechanism would be a second thing to get wrong.

**`snippetSupport` is measured before it is flipped.** Claiming `false` while
expanding snippets is dishonest and it is what this claim says today. But the
probe that produced everything above claimed `true`, so what changes for
sourcekit-lsp is *not known from these measurements* — and what it sends under
`true` includes nested closure placeholders:

    withTaskCancellationHandler(handler: ${1:{ ${2:Void} \}}, operation: ${3:{ ${4:T} \}})

which is a real change to what every Swift completion inserts, well beyond the
report. So: measure both claims against sourcekit-lsp first, then decide. If the
`false` answer is plain text with no placeholders at all, flipping is clearly
right; if it is the same text either way, the claim is cosmetic and can be fixed
without argument.

## Risks / Trade-offs

- **A request per keystroke inside every call.** `signatureHelp` triggered on
  `(` and retriggered on `,` and `:` is asked far more often than completion →
  Same debounce as completions, and asked only while the caret is inside an
  argument list or a snippet session is live. Cost is a design constraint here;
  say in the comment what was measured.
- **The nested-placeholder change is bigger than the report.** → Gated behind
  the measurement above, and separable: everything else in this change works
  with `snippetSupport` left as it is.
- **The doc panel doubles the popup's footprint on screen.** A 460-point list
  with a panel beside it near the right edge of a small display has nowhere to
  go → It goes on the side with room, and if there is room on neither it is
  not shown; the list is the thing that must never move.
- **Matching on `filterText` changes which items appear for every language.**
  More of them, which is the point, but it is a behaviour change in servers
  nobody reported a problem with → A test per server shape (label-is-signature,
  label-is-word) rather than a test for OpenSCAD only.
- **The stop-name-to-parameter match is a heuristic on one server's prose.** →
  Exact name or nothing, and a test with `cube`'s real documentation as the
  input so a change in openscad-lsp's wording fails loudly.
- **Two minutes of silence is still two minutes.** Saying "preparing" is honest,
  not fast; the first `.` in a cold Cadova package will still offer nothing for a
  while. That is 0501's territory and this change only stops lying about it.

## Open Questions

- Does sourcekit-lsp degrade to plain text when `snippetSupport: false`, or send
  placeholders regardless? Unmeasured, and it decides whether that claim changes
  in this item at all.
- Should the reducer favour a `parameters` section when the prose has one?
- Attributed runs for code fences, or plain text throughout in the first pass?
- Does the hint strip belong to `CodeView` or to `EditorViewController`? The
  snippet session lives in the view and the LSP conversation lives in the
  controller, and the strip needs both.
