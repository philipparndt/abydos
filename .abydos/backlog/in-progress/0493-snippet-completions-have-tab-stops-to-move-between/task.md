# 493. Snippet completions have tab stops to move between

> when editing scad files and writing "cube" + accept the suggestion from the
> LSP, then I am "cube(size = size, center = false);<<" with << being the cursor.

Everything in that line came from the server, and the caret is where we chose to
put it. openscad-lsp answers `cube` with

    "insertText": "cube(size = ${1:size}, center = false);$0",
    "insertTextFormat": 2

`Snippet.expand` leaves `${1:size}` as its default text and follows `$0`, which
the server put at the end — so the one word somebody has to replace is the one
word the caret is nowhere near, and `size = size` compiles as an unset variable
rather than as a mistake anybody notices.

**This is the feature 0326 named and did not build.** That item expanded
snippets so `union() $0` stopped going into files literally, and said in as many
words: *"Tab stops beyond the caret are left as their default text rather than
made navigable: jumping between them means holding ranges through later edits,
which is a feature and not this fix."* This is that feature.

## What was measured

The server ignores what we ask for. We advertise
`"completionItem": ["snippetSupport": false]` (`LSPClient.swift:319`), and
openscad-lsp 2.0.2 sends byte-identical replies with it true and with it false —
driven directly over `--stdio`, both ways, same `insertTextFormat: 2`. So there
is no capability to set that makes this go away, and a server that does honour
the flag would be giving us plain text we already handle.

## What exists to build on

- `Snippet.expand` (`Snippet.swift:34`) already parses the whole grammar and
  already finds the first stop — `firstStop` at `Snippet.swift:70` — and then
  throws it away in favour of `$0` on the last line of the function. The parse
  is done; what is missing is a shape that carries more than one offset out.
- `CodeView.applyCompletion` (`CodeView.swift:2548`) takes a single
  `caretOffset` and ends in `afterEdit(caret:)`. A stop is a *range* and it wants
  to be selected, not merely arrived at.
- The commit closure that joins them is `EditorViewController.swift:1493`.

## Worth deciding

- **What ends a session.** An edit outside the stops, Esc, or leaving the line
  are the usual answers; something has to, or the ranges outlive the reason they
  exist.
- **Who gets Tab.** The completion list already takes it to commit
  (`handleCompletionKey`, `EditorViewController.swift:1522`) and the list is gone
  by the time a session starts, so the two do not collide — but the document's
  own Tab does, and a session has to claim it and give it back.
- **Repeated stops.** `${1:x}` twice in one snippet is one stop in two places in
  every editor that does this properly. Worth knowing whether we mirror or take
  the first, before the ranges are written rather than after.
- **`--ignore-default` is a different lever, not this one.** The flag exists
  (`LanguageServers.swift:380` is where arguments go) and makes the server send
  `cube(size = ${1:size});$0` — fewer arguments, still `size = size`. It is a
  taste question about defaults and it does not need this item.

## Estimate

2026-08-15 15:58 — a couple of hours: the code is written, the build and the watching are not

## Steps

- [x] `Snippet` carries the stops it found — number, range, default — instead of
      one caret offset
- [x] Inserting a snippet selects the first stop, so typing replaces it
- [x] Tab and Shift-Tab move between the stops, and the last Tab goes to `$0`
- [x] The ranges survive typing inside a stop and editing elsewhere on the line
- [x] A session ends, by whatever was decided, and Tab goes back to the document
- [x] Repeated stops do whatever was decided, and a test says which — one stop
      at the first mention, no mirroring, and a nested stop is not one either
- [x] A `--snippet` driver, so what the keys do can be watched from outside the
      app rather than described
- [x] Watched in a `.scad`: `cube` + Tab, type `10`, Tab, and the line reads
      `cube(size = 10, center = false);`
- [x] Watched against a second server, so this is not shaped round openscad-lsp
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
