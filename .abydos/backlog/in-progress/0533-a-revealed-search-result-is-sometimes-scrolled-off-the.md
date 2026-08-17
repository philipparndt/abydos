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

## Steps

- [ ] A match is on screen after being revealed, in a file large enough to
      scroll, without depending on how many turns of the main loop have passed
- [ ] The reveal does not compute against a view that has not laid out — and
      says how it knows, rather than waiting longer
- [ ] A match far along a long line is visible horizontally
- [ ] Walking a file's matches with ↓ does not re-scroll one that is already
      on screen
- [ ] Watched on the reported file — 2028 lines, 143 matches of `public` — on a
      copy, and on a file with long lines
- [ ] A test that does not rely on timing, or a written reason there cannot be one
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/search.md` or `spec/editor.md` says what the project now does
