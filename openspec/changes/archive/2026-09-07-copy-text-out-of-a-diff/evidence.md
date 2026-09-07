# What the driven runs said

Every run below is `build/Abydos.app/Contents/MacOS/Abydos`, built with
`make build BUNDLE_ID=de.rnd7.abydos.diffsel PIN_UUID=0` and never installed,
against a throwaway repository under the scratchpad whose one file has a
tab-indented line, an emoji inside a string literal, and a rewritten block —
the three glyph cases the design says the highlight has to survive.

**The pull request page is not among them, and that is the one gap.** `gh` on
this machine is signed in to an internal enterprise host and not to
github.com, so the page that reads a pull request cannot answer here. Its diff
is the same `DiffView` every run below drives, and the read-only half of the
behaviour — which is what a pull request's diff is — is driven through the
history pane instead, where a commit's diff is read-only for the same reason.
`5.3` and `5.4`, which are about a *remark* in a diff, are the two tasks that
need the page itself; they are left undone rather than claimed.

## The complaint answered: select a word, three rows, then all of it

    --commit-page "select:Reader.swift,press:5@200,drag:5@240,word:5.20,copy,
                   press:3@200,drag:5@220,copy,all,copy,copy-key"

    COMMIT-PAGE drag: text 5.6-5.10
    COMMIT-PAGE word: 5.16-5.22
    COMMIT-PAGE copy:
    String
    COMMIT-PAGE drag: text 3.6-5.8
    COMMIT-PAGE copy:
    ext = try String(contentsOf: url)
    	return text
    	let tex
    COMMIT-PAGE all: 0.0-22.1
    COMMIT-PAGE copy:
    import Foundation

    func read(_ url: URL) throws -> String {
    	let text = try String(contentsOf: url)
    	return text
    	let text = try String(contentsOf: url, encoding: .utf8)
    	return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func announce(_ what: String) {
    	print("✅ \(what) read")
    	print("🎉 \(what) was read")
    	fflush(stdout)
    }

    struct Reader {
    	let url: URL

    	func lines() throws -> [String] {
    		try read(url).split(separator: "\n").map(String.init)
    		try read(url).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    	}
    }
    COMMIT-PAGE copy-key:
    keyboard in the diff: Copy enabled, ⌘C answered, clipboard holds |import Foundation|
    keyboard in the file list: Copy disabled, ⌘C reached nothing, clipboard empty

No marker, no number, no gutter — in every one of the three. The last two lines
are the whole of tasks 4.2 and 4.3: the press is AppKit's own key equivalent at
the real menu bar (`MenuKeyReport.presses(reaching:)`, so it is the press this
keyboard layout actually makes), the item has no target and reaches the diff
through the responder chain, and it is `validateMenuItem` that turns it off when
the keyboard is in the file list beside it. The clipboard is put back as it was
found, here and in the report itself.

**That report needs the window to be the key window**, and a launched run does
not always get it: one launch in three came back "Copy disabled, ⌘C reached
nothing" in both places, which is AppKit declining to route a key equivalent
into a window that is not frontmost rather than anything about the diff. The
same script in the same binary answers as above when the window has the
keyboard, and the two halves of the claim — enabled in the diff, disabled in the
list — are always the same way round.

## Where the press landed decides which selection it makes

    --commit-page "press:3@60,drag:5@60,selected,diff-menu,
                   press:3@200,selected,drag:5@260,selected,copied"

    COMMIT-PAGE press: lines 1 of them
    COMMIT-PAGE drag: lines 4
    COMMIT-PAGE selected: lines 4
    COMMIT-PAGE diff menu: Copy, —, Stage Selected Lines (3), —, Stash Selected Lines (3), —, Discard Selected Lines (3)
    COMMIT-PAGE press: nothing selected
    COMMIT-PAGE selected: nothing selected
    COMMIT-PAGE drag: text 3.6-5.12
    COMMIT-PAGE selected: text 3.6-5.12

x 60 is the number column and x 200 is the code. The numbers take lines and
offer everything they offered before, with *Copy* above it; the code takes
characters and no line is selected as a line. The press at x 200 that selected
nothing is the spec's own scenario — a click is how a selection is dismissed,
and it put the line selection away.

A hunk header still takes its hunk, however it is pressed:

    COMMIT-PAGE press: lines 4,5,9,10,17
    COMMIT-PAGE diff menu: Copy, —, Stage Selected Lines (9), —, Stash Selected Lines (9), —, Discard Selected Lines (9)

And nothing offered over a line selection moved. Two lines staged from the
numbers, then `git diff --cached`:

    COMMIT-PAGE stage-lines: 2 selected, applied

    @@ -1,8 +1,6 @@
     import Foundation
     
     func read(_ url: URL) throws -> String {
    -	let text = try String(contentsOf: url)
    -	return text
     }

Those lines and no others.

## Shift, double-click, triple-click

    COMMIT-PAGE drag: text 3.6-3.10
    COMMIT-PAGE press: text 3.6-6.12        (press:6@260+shift)
    COMMIT-PAGE copied:
    ext = try String(contentsOf: url)
    	return text
    	let text = try String(contentsOf: url, encoding: .utf8)
    	return text
    COMMIT-PAGE word: 5.16-5.22 → String
    COMMIT-PAGE row: 6.0-6.60 → 	return text.trimmingCharacters(in: .whitespacesAndNewlines)

Shift extends from where the gesture began, not from where it currently ends.

## The boundaries, either side of each one

    COMMIT-PAGE regions: x=2 numbers(row 5) x=118 numbers(row 5) x=122 text(row 5)

Unified, the code begins at 120. Side by side, both halves and the rule between
them:

    COMMIT-PAGE regions: x=2 numbers(row 3, left) x=67 numbers(row 3, left)
      x=71 text(row 3, left) x=118 text(row 3, left) x=122 text(row 3, left)
      x=300 text(row 3, left) x=304 numbers(row 3, right) x=370 numbers(row 3, right)
      x=374 text(row 3, right)

## A selection belongs to one side

    COMMIT-PAGE sides: side by side
    COMMIT-PAGE text: 3.10-8.20, right
    COMMIT-PAGE copied:
    = try String(contentsOf: url, encoding: .utf8)
    	return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func announce(_ what: String) {
    	print("🎉 \(what) w

The new file's lines, and only those. `text-left:3.10-4.11` on the same rows
gives the old file's:

    COMMIT-PAGE copied:
    = try String(contentsOf: url)
    	return tex

The screenshot beside it shows the highlight ending at the divider with nothing
drawn on the left.

## A hunk header inside a selection is copied as it is drawn

    COMMIT-PAGE text: 4.0-7.10
    COMMIT-PAGE copied:
    @@ hunk 1
    import Foundation

    func read(

## The measured rows, and where they go

    COMMIT-PAGE measured: 0 rows measured        (nothing drawn yet)
    COMMIT-PAGE text: 5.16-6.30
    COMMIT-PAGE measured: 2 rows measured        (the two rows the highlight covers)
    COMMIT-PAGE sides: side by side
    COMMIT-PAGE measured: 0 rows measured        (the rows were rebuilt)
    COMMIT-PAGE theme: 0 rows measured           (a theme change, at the diff's own door)

Two rows and not twenty-three: only what was drawn is measured. The `copied`
step between them builds nothing at all, which is the claim in task 4.1 — the
text comes from `GitPatch`, not from the layout.

## What a drag costs beside a scroll

    COMMIT-PAGE diff: 5200 rows
    COMMIT-PAGE timing: 5200 rows: dragged over them in 442 ms (5200 rows measured),
      drew them in 1345 ms, copied 167146 characters in 0 ms —
      load 2.1 over 16 cores (0.1 per core)

A drag down every row of a 5,200-row diff — a point per row, hit-tested through
Core Text — costs a third of what drawing the same rows costs. Copying all
167,146 characters of it is under a millisecond. The load is beside the numbers
because a number without it cannot be told from a regression.

**This number is the reason `DiffTextRun` is asked two questions and not one.**
When copying went through the same accessor the hit test uses, it asked for each
row's *origin* as well as its text — and an origin costs a text measurement,
because a line's text is drawn after a marker of measured width. Five thousand
of those turned the string join into 104 ms. `textAt` is the cheap question, and
the run above is with it.

The same claim with a bound on it, in the suite:

    DIFF COPY: 5000 rows joined in 0.6 ms — load 4.5 over 16 cores (0.3 per core)
    DIFF COPY: not bounding the join of a five-thousand-row selection —
      this run did not ask for it (make timing does).

and under `make timing`, which does ask:

    DIFF COPY: 5000 rows joined in 0.6 ms — load 6.0 over 16 cores (0.4 per core)
    ✔ Test copyingFiveThousandRowsIsAStringJoin() passed after 0.002 seconds.

## The read-only diff: a commit, in the history pane

    --log-page "file:0,text:2.4-3.20,copied,diff-menu"

    LOG-PAGE text: 2.4-3.20
    LOG-PAGE copied:
     step2() -> Int { 2 }
    func step3() -> Int 
    LOG-PAGE diff menu: Copy

A diff nothing can be staged from used to offer no menu at all. It offers
*Copy*, and copies the code.

## The file this grew, and where it went

`DiffView.swift` was 1,079 lines before this and 1,934 after, and
`Scripts/file-size.sh` — which `make warnings` runs first — has a 1,100-line
limit. Neither the proposal nor the design mentions it, and the check is right:
the state moved out rather than the braces.

    Sources/AbydosApp/Git/DiffTextRun.swift      the selection, the measured
                                                lines, and the arithmetic that
                                                turns a point into an offset
    Sources/AbydosApp/Git/DiffView+Drawing.swift the painting
    Sources/AbydosApp/Git/DiffView+Menu.swift    what a diff offers
    Sources/AbydosApp/Git/DiffView+Driving.swift what a driven run may ask
    Sources/AbydosApp/Git/DiffView.swift         984 lines: the view, its rows
                                                 and its two selections

`DiffTextRun` is the one that is a collaborator rather than an extension, and it
is the one that owns state: the view hands it two closures — what a row says,
and how a row is laid out — and never a row. Everything the three extensions
reach is named in the view and internal; nothing they reach is written from more
than one of them.

`ChangesPane`, `HistoryPane` and `SidebarController` are on
`Scripts/file-size-allowed.txt` and grew by the driven verbs above — 2497→2651,
1612→1640 and 1406→1546. Their recorded numbers are raised in the same commit,
which is what that file asks for.

## Task 2.1: no pixel moved

`text(of:)` and `textOrigin(of:)` were pulled out of `draw(row:)` and the
drawing now goes through them. The same script was run against HEAD and against
this change, with no selection made:

    diff before.out after.out   → REPORTS IDENTICAL
    cmp pixels-before.png pixels-after.png → SCREENSHOTS BYTE-IDENTICAL

Byte-identical, not merely alike.

## The photographs

Under the scratchpad, since a screenshot is not a thing to commit:

  * `shot-focused.png` — three rows selected, keyboard in the diff: the
    highlight behind the glyphs, after the marker, ending at the eighth
    character of the last row rather than at the margin.
  * `shot-unfocused.png` — the same selection with the keyboard in the file
    list, drawn in the unfocused colour.
  * `shot-sides.png` — side by side, a selection on the right-hand half only.
  * `shot-glyphs.png` — a tab-indented line and two rows with an emoji inside a
    string literal, selected end to end.
  * `shot-hunk.png` — a selection running from a hunk header, drawn in the bold
    face, down into the code.

## Before finishing

    make warnings   exit 0 — "No warnings in this repository's Swift", and the
                    length check green: DiffView.swift is 1,008 lines and off
                    the list, the three files that grew have their recorded
                    numbers raised.

    make test       exit 1 — 3,908 tests in 501 suites, 25 issues in two
                    suites, neither of them this change's:

      ExternalDependenciesTests.theOlderPerConfigurationLockFilesAreReadToo
        — expects a Gradle dependency with no artefact path, and this machine's
          ~/.gradle cache has the jar, so the answer carries a file URL.
      MermaidEveryKindLiveTests.everyKindOfDiagramIsAPictureAndNotAProgram
        — 22 diagrams that came back as the `<?abydos-mermaid?>` placeholder
          rather than a picture: the live renderer is not working here.

    DiffTextSpanTests               ✔ 8 claims
    DiffTextSpanCostTests           ✔ and the number, with its load

The two failing suites are in `Tests/AbydosKitTests` and test `AbydosKit`; this
change adds one unreferenced file there (`DiffTextSpan`) and everything else it
touches is `AbydosApp`, which that target does not link. So they cannot see it —
but they are red on this machine and this is not a claim that `make test` is
green.
