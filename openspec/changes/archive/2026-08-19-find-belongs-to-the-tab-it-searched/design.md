## Context

`EditorViewController` hosts one tab strip and every tab under it. Its own class
comment states the pattern the rest of the file follows:

> Each tab owns its own `CodeView` and scroll view rather than sharing one and
> swapping documents. Caret, selection, scroll offset and collapsed folds then
> survive tab switches for free, which is the behaviour you actually want and is
> far harder to get right by saving and restoring state by hand.

Find is the exception. Three things live on the controller rather than on `Tab`:

    private var findBar: FindBar!
    private var searchMatches: [SearchMatch] = []
    private var currentMatchIndex: Int?

and `activate(index:)` — sixty lines that swap the content view, move the
keyboard, re-report the caret, refresh the chrome — mentions none of them.

Two consequences, and the second is not in the report:

**The bar is open in every tab or none.** `showFind` sets `findBar.isHidden =
false` for the group.

**The matches belong to whichever tab was searched.** `stepMatch(by:)` ends with
`activeTab?.codeView?.setSearchMatches(searchMatches, current: next)`, and
`setSearchMatches` does `caret = range.upperBound` on a document that never
produced that range. `caret` is `private var caret = 0` with no clamp. Read from
the code; **not driven, because there is no verb that switches tabs after a
find** — adding one is a task, and what it finds is what goes in the spec.

The bar's second half is smaller and stranger. `notifyQueryChanged` already
turns the query red:

    // An unfinished regex is marked invalid rather than reported as "no
    // results", which would read as a wrong answer.
    let valid = TextSearch.isValid(query: query, options: options)
    field.textColor = valid ? .labelColor : Theme.current.gitConflict

But an invalid pattern is not stopped anywhere: `onQueryChanged` fires, `runFind`
runs, `TextSearch.matches` gets nothing out of a regex that never compiled, and
`setStatus(matchCount: 0, …)` writes **No results**. The comment's distinction is
made in the field and then thrown away in the label a few pixels to its right.

## Goals / Non-Goals

**Goals:**

- Find state — open, query, options, matches, current — belongs to the tab that
  produced it.
- A search with no results is visible without reading a word.
- A pattern that did not compile says that, rather than reporting on a search
  that never ran.
- No offsets from one document ever reach another's view.

**Non-Goals:**

- A `FindBar` view per tab. One bar for the group is right; only its contents are
  the tab's.
- Find state surviving a restart. Nothing else per-tab does.
- Touching the project-wide search pane. It is a different pane with its own
  results list, and it already handles an invalid pattern its own way.
- A theme key for "error". See below — it cannot be added without refusing
  every scheme that predates it.

## Decisions

**The state moves to `Tab`, all of it together.** Open-ness alone would leave the
matches shared, which is the fault with teeth. So `Tab` gains what the group
holds now — whether find is showing, the query, the options, the matches and the
current index — and the controller keeps only the one `FindBar` view. `activate`
gains one call that pushes the arriving tab's state into the bar and its matches
into its own `CodeView`.

The alternative — keeping the state on the controller in a dictionary keyed by
tab — was rejected for the reason the class comment already gives: state that
lives beside the thing it describes survives the thing being swapped, and state
in a side table has to be pruned when a tab closes by somebody remembering to.

**A PDF tab is a tab.** `pdfPreview` searches through `PdfFileView` and keeps its
own match count, so the tab's stored matches are empty for one and its query and
open-ness still apply. The bar is told what to show either way.

**The red is `gitConflict`, because the bar already chose it** — the invalid-regex
line above. Two reds for two states of one control would be a decision nobody
could read.

**A theme role of its own was ruled out on measurement, not taste.**
`Scheme.readApp` requires every `SchemeRole` that is not in `SchemeRole.optional`,
and a file missing one is refused whole — schemes are files people keep in
dotfiles repositories. `SchemeRole.optional` exists for exactly this problem and
has been used twice (`selectionBackgroundInactive`, then the two search-match
roles in 0536), but each member carries a *stated derivation* from roles that are
required. There is no other red to derive one from, so the derivation would read
`= gitConflict`, which is `gitConflict` with a longer name.

The naming is uncomfortable and worth writing down: `gitConflict` is a git name
for what every scheme actually stores as its red — `#FF5555` in dracula,
`#D6706E` in abydos and blue. `BacklogPalette` already borrows these five
deliberately, with the argument that a second green in one app means two greens
that mean different things. If a third non-git use appears, that is the moment to
rename the role with a derivation for compatibility. Not now, for one label.

**Both the query and the label go red, and the label is what says why.** Red now
means "this is not showing you matches", which is true of both an invalid pattern
and an empty result. What separates them is the words:

| query | field | label |
| --- | --- | --- |
| empty | plain | *nothing* |
| matches | plain | `3 of 17` |
| no matches | red | `No results` |
| will not compile | red | `Incomplete pattern` |

The last row is the one that changes twice: it says `No results` today, in grey.

**`Incomplete` rather than `Invalid`**, because the overwhelmingly common way to
reach it is having typed `(` and not yet the rest — the existing comment calls it
"an unfinished regex" and that is the right word for what somebody is doing.

**An empty query stays neutral.** It already shows no status; a field that goes
red when you clear it would be the bar shouting at you for closing the question.

**The invalid case does not run a search.** Today it runs one that cannot match.
Skipping it saves nothing worth measuring on a file this size — the point is that
the matches from the *previous*, valid query stop being cleared by a keystroke
that was only half of a bracket.

## What the driven runs showed

Two files in one group, against a scratchpad fixture: `long.txt`, 199 lines each
holding `widget`, and `short.txt`, five characters holding none. The search runs
in the long one, then the short one is selected and Next is pressed.

    before:        * long.txt   showing=true   matches=199  current=0  caret=13 of 4071
                     short.txt  showing=false  matches=0               caret=0  of 5
    after switch:  * short.txt  showing=false  matches=0               caret=0  of 5
    after step:    * short.txt  showing=false  matches=0               caret=0  of 5
    back:          * long.txt   showing=true   matches=199  current=0  caret=13 of 4071

Three things, and all three are the change:

- **Find is open in one tab and not the other.** `showing=true` for the file it
  was opened in, `showing=false` for the other. That is the report.
- **Stepping in the unsearched tab does nothing.** `caret=0 of 5`, unmoved. The
  199 matches are offsets into a 4071-unit document and the tab in front holds 5;
  they are not reachable from it any more, because they live on the tab that
  produced them.
- **Coming back restores it exactly** — query, matches, current index, and the
  caret at 13, which is where the first match left it.

**And driving caught one the code reading had missed.** After closing the tab
that had been searching, the report showed:

    bar showing=false query=“widget” says=“1 of 199”
    * 0 short.txt showing=false query=“” matches=0 caret=0 of 5

The tab's state went with the tab, correctly. The *bar* kept the closed tab's
query and count — hidden, so invisible, and waiting to be shown over a file that
knows nothing about it. It is the same class of fault as the matches were, one
level up: a control holding another tab's answer. `restoreFind` now empties the
bar for a tab that is not searching, rather than only hiding it.

## The query text will not go red, and this is where that stands

**Not done, and not for want of setting it.** The `No results` label is red —
sampled from the capture at `(212, 114, 112)`, which is the scheme's
`gitConflict`. The query beside it is white: 1007 glyph pixels averaging
`(236, 235, 235)`, none of them reddish, in the same picture. With matches, the
same white.

At the moment that picture was taken, every place the colour can live held red:

    query=“zzzznotfound” says=“No results” labelRed=true queryRed=true
    editor=red attributed=red

`field.textColor`, the field editor's `textColor`, and the attributed string all
red; the pixels white. **`NSSearchField` is not painting the colour it is given.**

Three ways forward were put up, and the one taken is **the label carries it**.
It is red, it is beside the query, and it is the half that says *what* is wrong;
the query going red would have been reinforcement rather than the signal. The
other two were a red border or tint on the field — which works with the control
as it is but is not what was asked for — and replacing `NSSearchField` with a
plain `NSTextField`, which is the only way to own the text colour outright and
means drawing the magnifier and the clear button by hand.

`colourQuery` stays in rather than being deleted. It costs one line, it is right
wherever the control does honour it, and removing it would also remove the
invalid-pattern marking that predates this change — which, by the same
measurement, was never visible either. That is worth saying plainly: the comment
beside it has claimed since it was written that an unfinished regex is "marked
invalid", and nobody has ever seen the mark.

Recorded rather than guessed at again: two builds went into colouring properties
that were already the right colour, and the third measured the pixels.

**And the photograph caught a third.** The first capture of a query with no
results showed `No results` in red beside a query still in plain white — the half
of the requirement that says *the query text* goes red, not working.

`field.textColor` is set, and it is not enough. A focused `NSTextField` hands its
text to a field editor, and that editor keeps the attributes it was given: the
property takes effect for text drawn later and leaves what is on screen alone.
The find field has the keyboard from the moment find is opened, which is exactly
when somebody is typing a query that finds nothing — so the case the requirement
is about was the one case it did not cover. The colour now goes to the field
editor and to its typing attributes as well, or the next character typed comes
out in the old colour.

Worth noting how it was found: not by reading, and not by a test — the test can
only ask what colour was *set*. A picture of the window is what showed the text
was still white.

**What was measured is the state after the fix, not the fault before it.** The
first run of this fixture had the search land in the file with *no* matches — the
last file named on the command line becomes the active tab — so it showed the
open-ness half and exercised nothing else. Reversed, it shows all three. The
fault itself remains read out of the code rather than watched: reverting to see
it would take `EditorViewController.swift` back past an unrelated change in the
same file, and past the driver verb doing the watching.

## Risks / Trade-offs

- **`activate` is the most careful function in the file**, carrying two fixed
  bugs about where the keyboard goes (items 510 and 523) with the measurements
  in comments. → The find restore goes in as its own call with its own name, and
  touches nothing about responders. The existing comments stay exactly.
- **Red now means two things.** → They are distinguished by the label, which is
  the change that also makes the existing comment true. A single meaning would
  need a second colour, which is worse.
- **Find state per tab is more state to get wrong**, including when a tab closes
  and when a preview tab is replaced. → It dies with the tab, which is the point
  of putting it there; a side table is what would need pruning.
- **A test that proves the stale-match path needs a driver verb** that does not
  exist. → That is a task, and the verb is worth having anyway: "find, then
  switch tabs" is a gesture nothing can currently drive.

## What was ruled out

**A scheme role of its own for the red.** `Scheme.readApp` requires every
`SchemeRole` outside `SchemeRole.optional`, and a file missing one is refused
whole — schemes are files people keep in dotfiles repositories, so a new required
role would refuse every scheme written before it existed. `SchemeRole.optional`
exists for exactly this and has been used twice, but each member carries a
*stated derivation* from roles that are required, and there is no other red to
derive one from: the derivation would read `= gitConflict`, which is
`gitConflict` with a longer name. The naming is uncomfortable — `gitConflict` is
a git name for what every scheme file actually stores as its red, `#FF5555` in
dracula, `#D6706E` in abydos and blue — and `BacklogPalette` already borrows
these five deliberately. A third non-git use is the moment to rename the role
with a derivation for compatibility. Not now, for one label.

**A `FindBar` view per tab.** Three tabs open would be three search fields laid
out and themed for no gain. The bar is chrome for the group; only its contents
are the tab's.

**Keeping the matches on the controller and only moving the open-ness.** That
fixes the reported half and leaves the half with teeth: offsets into one document
handed to another's view, setting a caret from a range that document never
produced.

**A side table keyed by tab.** It would need pruning when a tab closes, by
somebody remembering to. State on the thing it describes goes when the thing
goes — which the driven run then confirmed, and which also showed the one place
state was still left behind: the bar itself.

**Re-running the search when a tab comes back.** Its matches are already known
and kept, so re-running would be work whose answer is in hand — and it would move
the current match, since `runFind` starts from the caret.

**Find state surviving a restart.** Nothing else per-tab does.

## Open Questions

- Should closing the bar in one tab close it everywhere, as a deliberate
  gesture? Proposed: no — ⌘F and Escape are per tab like everything else. But
  somebody who uses find as a mode rather than a question may disagree after a
  week.
- Should the query be shared as a *default* — open find in a new tab and get the
  last thing you searched for, rather than an empty field? Xcode does. Left out:
  it is a separate decision about seeding, and `showFind` already seeds from the
  selection, which is the better answer when there is one.
- `No results` when the file is empty, or when it has not finished loading, are
  the same words for different situations. Neither is common enough to name yet.
