## Why

The find bar is one view per *editor group*, and a group holds every tab in it.
`EditorViewController` owns `findBar` alongside the tab strip, and `activate(index:)`
— the whole of switching tabs — touches nothing about find. So opening find in one
file opens it in every file in that group, and closing it closes it everywhere.

That is the report, and it is the smaller half of what is wrong. **The matches
are shared too**, and they are a different file's:

    private var searchMatches: [SearchMatch] = []
    private var currentMatchIndex: Int?

Both live on the controller. `runFind` fills them from the active tab's document;
`activate` does not clear them. Switch tabs with the bar open and press Return,
and `stepMatch(by:)` reaches

    activeTab?.codeView?.setSearchMatches(searchMatches, current: next)

which hands file A's UTF-16 offsets to file B's view. `setSearchMatches` then does
`caret = range.upperBound` against a document that never produced that range, and
`caret` is a plain stored property with no clamp on it. **Read from the code rather
than driven** — there is no verb that switches tabs after a find, which is why one
of the tasks below is to add one and see what actually happens.

Every other piece of per-tab state in this controller is already per-tab, and the
class comment says why: each tab owns its own `CodeView`, so "caret, selection,
scroll offset and collapsed folds then survive tab switches for free, which is the
behaviour you actually want and is far harder to get right by saving and restoring
state by hand." Find is the one thing that was left on the group.

The second half of the report: a query that matches nothing says **No results** in
the same grey as `3 of 17` — one word in the corner, in the colour used for
everything else that is merely informational.

The bar does already have a red, and finding it changes what this should do.
`notifyQueryChanged` sets the field's text to `Theme.current.gitConflict` when the
query is a regex that will not compile, with the reason written beside it:

    // An unfinished regex is marked invalid rather than reported as "no
    // results", which would read as a wrong answer.

**That distinction does not survive the label.** An invalid pattern still reaches
`runFind`, which gets no matches from a regex that never compiled, and `setStatus`
says `No results` — the exact reading the comment set out to avoid. So the bar
today says "no results" for a pattern it never ran, and says it in grey, while
turning the text red for a reason it does not name.

## What Changes

- **Find belongs to the tab.** Whether the bar is open, what is in it, which
  options are set, the matches and which one is current — all move from the
  controller to `Tab`, beside the `CodeView` that owns the text they are offsets
  into. Switching tabs shows that tab's find state; switching back shows it again.
- **One bar, still.** The view stays a single instance at the top of the group —
  this is about which state it displays, not about building a bar per tab. What
  changes is that `activate` now tells it what to show.
- **A search that found nothing looks like it.** The query text and the `No
  results` label both go red — `gitConflict`, which is what the bar already uses
  for an invalid pattern and what every scheme file stores as its red.
- **And an invalid pattern stops claiming there were no results.** Once red means
  two things, the label is what tells them apart, so a pattern that did not
  compile says so instead of reporting an answer to a search that never ran. This
  is not scope creep: it is the sentence already written in that file, made true.
- **The stale-match path stops existing**, because the matches move to the tab
  that produced them. Whether it was reachable as a crash or only as a wrong
  caret is answered by a test, not by this paragraph.
- **Not proposed: a find bar per tab as a view.** Three tabs open would be three
  search fields laid out and themed for no gain; the bar is chrome for the group
  and only its contents are the tab's.
- **Not proposed: remembering find state across a restart.** Nothing else in the
  editor's per-tab state survives one either.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `editor`: find-in-file already lives here — the current match being the loudest
  thing on the page, the highlight colours, the bands on wrapped rows. This adds
  which tab that state belongs to, and what the bar looks like when the answer is
  nothing.

## Impact

- `Sources/AbydosApp/Editor/EditorViewController.swift` — `findBar`,
  `findBarHeight`, `searchMatches`, `currentMatchIndex`, `showFind`, `closeFind`,
  `setFindQuery`, `runFind`, `stepMatch`, `isFindVisible`, and `activate(index:)`,
  which is the one that does nothing today and has to.
- `Sources/AbydosApp/Editor/EditorViewController.swift`'s `Tab` — gains the find
  state, beside `codeView` and `document`.
- `Sources/AbydosApp/Editor/FindBar.swift` — `setStatus` and
  `notifyQueryChanged`, which is where the field's colour is already decided and
  where the two meanings of red have to be told apart.
- A PDF tab searches too (`pdfPreview`, `PdfFileView.clearFind`), and it has its
  own match count. It is a tab like any other and gets the same treatment.
- No new dependency. Nothing new on the drawing path: the bar is told what to
  show when a tab is activated, which is not a per-frame path.
