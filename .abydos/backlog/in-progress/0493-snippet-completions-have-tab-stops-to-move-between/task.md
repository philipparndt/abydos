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

## What was decided, and what was ruled out

The four questions above, answered, and the answers that were tried first.

- **What ends a session: an edit anywhere but the stop being typed into,
  Escape, and Tab off the last stop.** The rule is deliberately narrow, and the
  reason is that the alternative cannot be done honestly: to survive an edit
  somewhere else, a stop has to be *guessed* forward, and a wrong guess puts
  the caret in the middle of a word half a line away rather than failing. A
  session that simply ends is a Tab that indents, which is what somebody
  expects from an editor that is no longer doing anything.
- **Ruled out: ending it when the caret leaves the stops.** Tried, and it is a
  hook in `setCaret`, in the mouse handler, and in anything else that moves the
  caret — three places to forget. Nothing goes wrong if the session outlives a
  click, because the ranges are still true: an edit is what invalidates them,
  and an edit already ends it. So the caret is checked lazily, at the one
  moment it matters — `covers(caret:)` when Tab is pressed — and Tab after a
  click somewhere else indents.
- **Tab off the last stop eats the key** rather than inserting a tab. Neither
  is obviously right; a swallowed Tab at the end of a call somebody has just
  filled in is invisible, and a tab character in the middle of one is not.
- **Ruled out: mirroring a repeated `${1:x}`.** Every editor that does this
  properly types into both at once, and doing it badly is worse than not doing
  it: the second copy keeps the *old* default and ships in somebody's file. One
  stop at the first mention, the second left as text, and a test that says so.
- **Ruled out: nested stops.** `${1:${2:i}}` would give two ranges of which one
  contains the other, and typing into the outer one destroys the inner. Only
  top-level stops are visited.
- **Ruled out: following the edits from `CodeView`'s own editing methods.** They
  all call `document.replace`, so it looked like a small change to route them
  through one helper — but that is ten call sites, and it would miss undo,
  redo, and a workspace edit arriving from a rename. `TextDocument.onTextReplaced`
  is one hook that sees all of them, and it is the same shape as the
  `onLinesChanged` breakpoints already use. Its offsets are only worked out when
  something is listening.

### What surprised

- **The stops are not in the order they appear in the text.** rust-analyzer
  answers `match` with `$0` sitting *inside* the braces, textually before the
  arm it wants filled in first. So what moves a stop along after an edit has to
  be where it is, not when it is visited — which is a different loop from the
  one written first, and `movesStopsThatSitAfterTheEditWhicheverOrderTheyAreVisitedIn`
  is that lesson.
- **`#expect` cannot call a mutating member** — `$0.edited(…)` inside the macro
  expansion is immutable. Hence a local before each check in
  `SnippetSessionTests`, which reads worse and is the only thing that compiles.
- **`swift build` is not the build.** A bare one here ran under Swiftly's
  6.1.2 rather than Xcode's toolchain — visible in the `swift-frontend`
  processes, which is the only way it announces itself — and was stopped and
  rerun under `make`. The Makefile pins `xcrun swift` for exactly this and says
  why; `make test` and `make build` are the verbs.

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
- [x] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
