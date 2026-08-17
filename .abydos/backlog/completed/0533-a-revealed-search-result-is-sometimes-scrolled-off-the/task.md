# 533. A revealed search result is sometimes scrolled off the screen

> there are some issues in the search: when searching for "public" in
> […]/Data/ContentSession.swift
>
> The current selected search result is sometimes out of the screen for example.
> This happens for all files.

Reported against a 2028-line file with **143 matches** of `public` in it, and
said to happen everywhere rather than in that one file — which is what the code
below predicts.

## The single async hop, which is a guess and not a guarantee

`EditorViewController.open(fileURL:atLine:)` ends:

    // Deferred: a freshly opened document has not laid out yet, so scrolling
    // now would compute against a zero-height view.
    let opened = activeTab
    DispatchQueue.main.async { [weak opened] in
        opened?.codeView?.reveal(line: line)
    }

The comment has the diagnosis exactly right and the remedy only sometimes. One
turn of the main loop is not "layout has finished" — it is "one turn of the main
loop has passed". Where the work takes two turns, or where it is itself
scheduled asynchronously, the reveal runs against a view that is still wrong and
scrolls somewhere that is not the match.

What it computes against, in `CodeView.reveal(line:column:)`:

    if let point = caretPoint(), let scrollView = enclosingScrollView {
        let height = scrollView.contentSize.height
        let y = max(0, point.y - height / 2)

Both halves depend on layout. `caretPoint()` goes through
`point(forUTF16:)` → `firstVisualRow(forDocumentLine:)` and, with word wrap on,
`wrapSegmentForOffset` — so it needs the wrap layout `updateFrameSize()` builds.
And `scrollView.contentSize.height` is the clip view's, which is wrong before the
pane has been given its size. Centring against a wrong height puts the line off
by half a pane; centring against a wrong `point.y` puts it anywhere at all.

**This is not new, and it is newly constant.** Until today the reveal ran when
somebody pressed ⏎ on a result. 0529 made search show each match *as the
selection moves*, so walking 143 matches with ↓ now runs this path 143 times,
every one of them a fresh race. That is why it reads as a search bug.

## The second one, which is not a race at all

    scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))

The horizontal offset is **forced to zero** on every reveal. A match far along a
long line — a string literal, a wide call, anything past the pane's width — is
scrolled out of view horizontally and stays there, reliably, however long layout
has had. `reveal` takes a `column` and uses it to place the caret, then throws
away the one part of the answer that says where to look sideways. `public` sits
near the start of its line so the report is unlikely to be this, but it is the
same sentence for somebody searching for a string.

## Worth deciding

- **How to know layout is done, rather than betting on a turn count.** Adding a
  second `async` would make the bet longer and still a bet. The honest shapes:
  the reveal is a *pending request* the view drains once it has laid out, or
  `reveal` measures and forces layout itself before computing. The second is
  smaller; the first survives a document that lays out lazily.
- **Whether `reveal` should refuse to scroll rather than scroll wrongly.** A
  `caretPoint()` of nil is already handled — the `if let` simply does not
  scroll. A point computed against stale layout is worse than none, and is
  currently indistinguishable from a good one.
- **What horizontal reveal should do.** Not "scroll to the column" — a match
  eighty characters in should not put the start of the line off the left edge.
  Keeping the match within the pane, and leaving the offset alone when it is
  already visible, is the behaviour every editor has.
- **Whether the walk should re-centre a match already on screen.** With 0529, ↓
  through matches in one file now re-scrolls for each. If the next match is
  already visible, moving the view under somebody's eyes is worse than leaving
  it. This is the same question the item's own "a row already showing is not
  opened again" rule answered for tabs.
- **Whether one reveal is enough after a *fold* changes.** `reveal` calls
  `folding.reveal(line:)` first, which can change every line position beneath
  it; the frame is updated after, but this is worth checking rather than
  assuming, since it is the same class of ordering bug.

## What was decided

**Both of the honest shapes, not one.** `CodeView.reveal` calls
`layoutSubtreeIfNeeded()` on the window's content view before it measures
anything, so the pane it centres against has been given its size *by the layout
pass* rather than by a turn of the main loop going by. And where after that there
is still nothing to measure — no window, a viewport of no height — the request is
recorded in `pendingReveal` and `viewportChanged` drains it when the clip view is
given a frame. The second is a belt to the first's braces, and it is what makes
"not laid out" a *deferral* rather than a wrong scroll.

**`reveal` does refuse.** `RevealScroll.answer` has three answers, and
`notLaidOut` is one of them. A point measured against a viewport of zero is worse
than no point, and the caller cannot mistake one for the other any more.

**The async hop is gone rather than lengthened.** With the reveal synchronous,
what its comment was defending against goes too: there is no interval in which
the active tab can change, so `abydos deep.txt:150 main.go` cannot reveal line
150 on the two-line file. That is why the weak capture of `activeTab` is not in
the new code — it was guarding a window that no longer exists.

**A match is a span, not a point.** The first cut asked whether the match's
*start* was inside the pane, which calls a forty-character match that begins one
column inside the right edge "visible" with most of itself off screen.
`answer(bringing:width:onScreenIn:)` takes the width, `SearchMatch` carries its
column, `LSPRange.widthOnOneLine` says how wide a symbol is, and the hops between
a result row and the editor carry the whole match rather than a widening tuple of
loose integers.

**Sixteen columns of context, judged by eye and not by taste alone.** Eight left
`public` on screen with two columns to spare and the next word cut in half —
visible and still not readable. See `images/`.

**A fold changing line positions was checked and is not a second ordering bug.**
`folding.reveal(line:)` is followed by `updateFrameSize()` *before* anything is
measured, in both reveal paths, so the rows a point is worked out from are the
rows the unfold left behind. It was the last worry on the list and it costs one
line to confirm rather than assume.

## Ruled out on the way

- **A second `async`, or a delay.** Not tried, on the item's own argument: it is
  the same bet, longer. Worth writing down that it was *available* and would have
  passed the driven walk on this machine — which is exactly why it is the wrong
  answer.
- **"It is a search bug."** It is not. Both faults are in the editor's reveal;
  0529 only made the path run 143 times instead of once, which is why it started
  being reported now.
- **The reported file is not the horizontal case.** Its longest line is 116
  characters, so `public` in `ContentSession.swift` is never off the side. The
  sideways fault is real and needed a fixture of its own — `LongLines.swift`, with
  matches at column 262 — which is what the item predicted.
- **`measureLongestLine` as a *third* cause, which it turned out to be.** It
  answers off the main thread and leaves 120 columns standing in, so the document
  view can be narrower than the line being revealed and the scroll clamps short of
  the match — off the screen, for a reason that has nothing to do with layout
  timing or with `x: 0`. `widenForTheLongestLine` measures the one line being
  revealed first. Found by reading the clamp, not by seeing it.
- **Whether the pending reveal is dead code.** In every case that could be driven
  — a fresh tab, a walk crossing into a second file, a maximised panel that has to
  make room for the editor first, the last match of a 2028-line file — forcing
  layout was enough and `pending` came back `false` every time. It is kept
  because the alternative for a pane with no window is to scroll to a number
  measured against nothing, and because `notLaidOut` must not silently mean "do
  not scroll". It is not exercised by the driven runs, and that is stated here
  rather than left to be discovered.
- **A blank band under the editor in one screenshot.** One capture with the find
  bar open and no `--panel-height` came back with the editor's scroll view ending
  60 points above the status line. It did not reproduce with an explicit panel
  height, and the reveal cannot cause it: nothing here sets the scroll view's
  frame — only the document view's size and the clip view's *origin*. Left as the
  panel split's business, not this item's.
- **Driving the app at all nearly went wrong twice, in ways worth reading**: see
  the note at the end.

## Watching it from outside

`--search-steps` grew a `shown` step, which prints what the *editor* is showing
after the row the walk landed on: the caret's line, whether its point is inside
the visible rect, the offset the pane is scrolled to, and whether a reveal is
still pending. A driver that had to compare two numbers itself would be
reimplementing the thing under test, so the verdict is in the line.

The reported file, copied into a scratch project, walked with ↓ and jumped about
with `select:` — every row `on=yes`:

    SEARCH shown: ContentSession.swift line=21   on=yes point=90,480    visible=0,272+1084x415
    SEARCH shown: ContentSession.swift line=22   on=yes point=270,504   visible=0,272+1084x415
    SEARCH shown: ContentSession.swift line=25   on=yes point=270,576   visible=0,272+1084x415
    SEARCH shown: ContentSession.swift line=40   on=yes point=270,936   visible=0,728+1084x415
    SEARCH shown: ContentSession.swift line=46   on=yes point=120,1080  visible=0,728+1084x415
    SEARCH shown: ContentSession.swift line=2020 on=yes point=120,48456 visible=0,48248+1084x415
    SEARCH shown: LongLines.swift      line=51   on=yes point=2040,1200 visible=1129,1000+1084x400

Three things are in those lines. The band `visible=0,272` repeated across lines
21, 22 and 25 is the **re-scroll that no longer happens** — three matches shown
without the view moving. Line 2020 of 2028 is the far jump landing on screen.
And `point=2040` inside `visible=1129+1084` is the **horizontal** answer: the old
code forced that offset to 0, which put the match 950 points off the right edge
by construction.

## Steps

- [x] A match is on screen after being revealed, in a file large enough to
      scroll, without depending on how many turns of the main loop have passed
- [x] The reveal does not compute against a view that has not laid out — and
      says how it knows, rather than waiting longer
- [x] A match far along a long line is visible horizontally
- [x] Walking a file's matches with ↓ does not re-scroll one that is already
      on screen
- [x] Watched on the reported file — 2028 lines, 143 matches of `public` — on a
      copy, and on a file with long lines
- [x] A test that does not rely on timing, or a written reason there cannot be one
- [x] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [x] `spec/editor.md` says what the project now does

## The test, and what it can and cannot say

`RevealScrollTests` is nineteen tests over `RevealScroll.answer`, which takes the
pane as a value and returns one of three answers. No window, no main loop, no
turn count, and nothing that passes because a machine was fast: the `notLaidOut`
cases are asserted by *asking* about a viewport of no height, which is the state
the old code could not tell from a good one.

What a test cannot say without a window is that the *view* asks the question at
the right moment. There is no test target for `AbydosApp` — the app layer is
driven from outside instead — so that half is the `shown` step above, run against
the reported file. The division is the project's existing one: `PanelRowSnap` and
`ResultChecklistKeys` are the same shape of answer for the same reason.

## A note for whoever drives the app next

Two things cost most of an hour here and neither is in this item's code.

**A driven run showed a project nobody passed to it** — which is item **0534**,
filed while this was being worked on, and this is the reproduction it asks for.
`--open <scratch>` opened the scratch project correctly, and then the window
*followed its terminal* somewhere else: `followsTerminalProject` is `true` in the
real preferences, a driven run copies the real domain into its volatile one, the
panel's shell inherited a working directory that no longer exists, and zsh
fell back to `~/.config/zshutil`. `onPaneNeedsProject` then switched the project
out from under the run, discarding the tab `--file` had opened —
`--print-text` said `no editor` and `--close-window` reported "a window showing
zshutil". Nothing was typed and nothing was written, exactly as 0534 says. The
way past it, for anybody who needs a driven run *now*: build with a bundle
identifier of your own (`make build BUNDLE_ID=…`) and seed that domain with one
key first, so `Settings.migrate` finds it non-empty and does not copy the real
one in — then `followsTerminalProject` is the registered default of `false`.

**The app hangs on launch with no output** if a previous driven run was killed:
macOS puts up "reopen windows?" from `promptToIgnorePersistentState`, modally,
before `applicationDidFinishLaunching`, so even `--version` prints nothing and
waits. `-ApplePersistenceIgnoreState YES` after the verbs gets past it. A `sample`
of the hung process is what found this, and is the fastest way to identify it
again.
