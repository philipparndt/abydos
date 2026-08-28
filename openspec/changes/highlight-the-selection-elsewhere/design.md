# Design

## Context

A row of the editor is already painted in four passes, and their order carries a
decision. The line background goes down first; then the find matches that are not
current, *under* the selection; then the text and the selection; then the current
find match, *over* the selection. The last of those is item 0536 written into the
paint order: revealing a match selects it, so the two cover the same pixels, and
the selection painted second turned the one match meant to be findable at a glance
into the dimmest thing on the page — 5.6 against the ground before, 1.4 after.

So a third band is not a free addition. It arrives on a row where three things
already state a precedence, and it has to take a place in that order rather than
be layered wherever it happens to be convenient.

The rest is in hand. `searchHighlights(docLine:segment:rect:)` turns UTF-16 ranges
into rectangles for one visual row, wrap boundaries included; `TextSearch` finds
literal occurrences with a cap; `reportCaretPosition` is called from all nine
paths that move the caret or extend a selection, drag included.

Two constraints come from the repository. Anything worth a test is a value in
`AbydosKit`, because `Tests/` reaches nothing in `AbydosApp`. And this runs while
somebody drags a selection across a paragraph, which makes its cost part of its
design rather than something to measure afterwards.

## Goals / Non-Goals

**Goals:**

- The other places a selection's text appears, visible without opening anything.
- Quieter than a find match, because nobody asked for it.
- Gone the instant it stops being true — the selection changes, or the text does.
- No scan while somebody is dragging, only when they stop.

**Non-Goals:**

- Symbols. This is a run of characters, not an identifier: `count` lights the
  `count` inside `accountId`, and that is the chosen behaviour rather than a
  limitation. What a *symbol's* uses are is the language server's answer and
  already has a verb — Find Usages.
- The word under the caret with no selection. Considered and not chosen: bands
  that appear and move as the caret walks a line are motion nobody asked for.
- A count, a next/previous, or anything to press. This is a thing to see.
- Scrollbar marks. The bands are on the page; a map of the file is its own change.
- Changing find in any way.

## Decisions

### Two characters, one line, and not all whitespace

A selection lights its twins when it is at least two characters, holds no line
break, and is not only whitespace.

One character would band every `e` on the page — a screen of noise carrying no
information, since the answer to "where else is `e`" is "everywhere". A selection
spanning lines is a block being moved or deleted, not a thing being looked up. A
run of spaces is an indent, and every indent in the file matching is the same
noise as `e` with more of it.

*Ruled out: whole words only, the way IntelliJ does it.* It answers a better
question — `count` not lighting inside `accountId` — and it answers a different
one: selecting `x + y` or `unt` would then highlight nothing, and a feature that
does nothing for half the selections somebody makes teaches people not to rely on
it. A literal rule is one somebody can hold in their head.

*Ruled out: a minimum of three characters, or a maximum length.* Two is the
shortest selection anybody makes on purpose; a maximum is a rule with no failure
behind it.

### Case-sensitive, literal, whole file

`Count` does not light `count`. A selection is exactly the characters somebody
dragged over, and a highlight that quietly matched more than that would be
claiming an identity the text does not have.

The scan covers the whole file rather than the visible rows.

*Ruled out: scanning only what is on screen.* It is the obvious saving — bands
are only drawn for visible rows — and it moves the work into scrolling, which is
the one thing in this editor that must not acquire a per-frame scan. A whole-file
scan happens once per selection; a visible-range scan happens on every scroll.

### The scan is debounced, and the bands go the moment the selection does

On a selection change the bands are dropped at once and the scan is scheduled on
the same debounce find already uses. Dragging a selection across a paragraph
therefore costs one scan, at the end.

Dropping first is not a flicker to be avoided here, unlike the find matches after
an edit: the selection *is* the query, so when it changes every band is about a
question nobody is asking any more. There is nothing to carry over and nothing to
adjust — the honest state between the change and the answer is no bands at all.

### Find wins while it has matches

While the view holds find matches, no occurrence bands are drawn or scanned.

Two kinds of band on one page meaning two different things is worse than one kind
meaning one thing, and the one somebody asked for is find's. It also settles the
layering question by removing it: the new band never shares a row with a find
match, so the order that 0536 established is untouched.

*Ruled out: drawing both, in different colours.* It is what VS Code does and it
needs a third colour that separates from the find band, from the selection and
from the ground, in five schemes and two lightnesses. The band would also mean
"the same text is here" in both cases, which is the same sentence said twice in
two voices.

### The bands sit where the non-current find matches sit

Under the selection, over the line background — the depth find's other matches
already use, and for the same reason: what is selected is stated by the selection,
and a band over it would be one claim covering a louder one.

### A colour of its own, derived rather than demanded

A new `SchemeRole` joins the `optional` set with a derivation from colours a
scheme already has, quieter than `searchMatchBackground` — a find match is an
answer somebody asked for and this is not.

The mechanism is already built and already argued for: schemes are files people
keep in dotfiles repositories, and a colour that arrived later must not refuse
them. What a file that leaves it out gets is written down rather than defaulted
silently.

**Corrected while implementing.** This first said no scheme file needs editing.
That is true of somebody's own file and false of the ones this repository ships:
`everyBundledSchemeChoosesTheRolesItCouldLeaveOut` requires every shipped scheme
to state every optional role, on the grounds that the derivations are for schemes
nobody has looked at and ours have been. So all four state it, each measured
against its own ground and its own find band rather than derived.

The derivation is from the *selection* rather than from the find band, which the
measurement settled: halfway from the ground to the find band leaves 1.11–1.12
against the ground in the light schemes, below their find bands' own 1.23–1.26
and too faint to see. Halfway to the selection says the truer thing anyway —
these are the places that would look selected if you selected them.

*Ruled out: reusing `searchMatchBackground`.* No new role, no derivation, and the
two would be indistinguishable — which is tolerable only because find wins while
it is showing, and that is an argument from a rule that could change rather than
from what the two things are.

### Where the scan hangs

`reportCaretPosition` is called from every path that moves the caret or extends a
selection, `mouseDragged` included. The scan is scheduled from there.

That function's name is about the caret and it now also means "the selection may
have changed", which is worth saying out loud rather than leaving to be
discovered. The failure mode is bounded and visible: a path that moves a
selection without reporting the caret gets no bands, which is nothing drawn rather
than something wrong drawn.

*Ruled out: a hook of its own called from all nine sites.* Nine call sites to
keep in step, and the tenth one somebody adds later is the one that gets it
wrong.

An edit is the other way the bands can stop being true — an agent rewriting the
file with a selection standing — and it goes through the same schedule, on the
`onTextReplaced` path `find-and-replace` fanned out through the view.

### What is worth highlighting, and where, is a value in `AbydosKit`

Both halves — whether a selection qualifies, and where its text appears — are
functions of a string and a text. They go in `Sources/AbydosKit/Search/` with
tests, and the view draws what it is given. It is the only part of this that can
be tested at all.

## Risks / Trade-offs

- **A scan of the whole file on every selection** → debounced to one per pause,
  bounded by `TextSearch.matchLimit`, and skipped entirely while find is showing
  or the selection does not qualify. The cost is the same scan typing in the find
  field already pays on the same debounce.
- **A common short selection bands most of the page** — selecting `if` in a large
  file → true, bounded, and self-correcting: the person selected it and can see
  what it did. The two-character floor takes the pathological case away; a
  cleverer rule would be guessing.
- **Partial-word matches surprise somebody expecting IntelliJ** → it is stated in
  the requirement and it is the behaviour that never does nothing. Find Usages
  remains the symbol answer.
- **The new role's derivation lands badly in some scheme** → `SchemePair.midway`
  cannot be louder than the louder of the two colours it sits between, which is
  the bound the existing derivations already rely on.
- **A path that moves the selection without reporting the caret** → no bands,
  which is the safe direction, and the same funnel the caret indicator already
  depends on.

## Open Questions

- Whether a selection made by a verb rather than by hand — Select All, a reveal
  that selects a match — should light anything. Select All is excluded by the
  line-break rule in any file with more than one line; the reveal case is
  excluded while find is showing. Both fall out of rules already made, so nothing
  is decided here until one of them is wrong in use.
- Whether the bands belong on the scrollbar as well. Wanted eventually; a map of
  the file is a change of its own and would want the find matches on it too.
