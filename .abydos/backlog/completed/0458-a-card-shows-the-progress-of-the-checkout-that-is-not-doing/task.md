# 458. A card shows the progress of the checkout that is not doing the work

An agent works an item in a worktree of its own and ticks `## Steps` there. The
board reads the project's copy. So the fraction on the card is the fraction as it
was when the item was picked up, and it stays there until the branch is merged —
which is exactly when nobody needs to watch it any more.

Measured while 0454 was being worked:

    project copy   0 of 6 ticked
    branch copy    3 of 6 ticked

**`AGENTS.md` promises the opposite**, in step 5 of picking up a ready item:

> tick each step in the commit that finishes it … and the board in the app shows
> the same number on the card — so somebody watching can tell what is done and
> what is still missing without asking.

That sentence is false for every item started with `abydos-backlog start`, which
is all of them. Whatever else this item does, that sentence has to become true or
go.

## Why the state is right and the progress is not

This is *not* the same as the folder. `AGENTS.md` is deliberate that an item
stays in `in-progress/` in the project until the branch lands — "the item is
finished when the work is, and the work is in a branch nobody has taken yet" —
and that is correct: the project's copy is the answer to "what is nobody working
on", and an item finished on a branch nobody has merged is still not done here.

The checklist answers a different question — *how far along is the work* — and
the work is on the branch. So the honest split is **state from the project,
progress from the worktree**. Same for the two other things a card reads from the
item and that an agent changes as it goes: the image count and whether there is a
spec delta.

## Decided: option 1, and the number says where it came from

Chosen, with two additions asked for explicitly: **the card shows that the
fraction came from a worktree**, and **the worktree's folder can be revealed**.
The options below are kept as the reasons the others were not taken rather than
as a choice still open.

Revealing is a third thing to do with a worktree, beside the two 0445 already put
on the card's menu — "Open Worktree as a Project" and "Open Terminal in
Worktree". This one is Finder, for when somebody wants the files rather than the
project or a shell, and it belongs beside them under the same `isPresent` guard.

## An ETA, maintained by whoever is doing the work

Asked for alongside the above: an agent working an item keeps an estimate of how
much longer it has, and the card shows it beside the fraction.

**It has to be the agent's, not arithmetic.** The tempting version is
`elapsed / done × remaining` from `BacklogRun.startedAt` and the checklist, which
needs nobody to write anything — and it is wrong in the way that matters: steps
are not the same size. An item that ticks three small ones in ten minutes and
then spends two hours on the fourth would show twenty minutes remaining for the
whole of those two hours, and be most confident exactly when it is most wrong.

**So it carries when it was said.** An estimate is a claim with a time on it, and
a card showing "about an hour" without saying whether that was judged four
minutes ago or four hours ago is the same failure as the profile that names the
wrong function confidently: a number believed because it is displayed. Stale
should look stale — the card can grey it, or say "an hour, as of 14:20", but it
must not present an old guess as a current one.

Two more things to settle while building it:

- **Where it lives.** The item's markdown is the obvious home, since it travels
  with the work and this whole item is about reading the worktree's copy. A
  header line or a `## Estimate` section, whichever reads better beside `## Steps`
  — but one place, parsed the way `## Steps` is, and absent when nobody has said.
- **`AGENTS.md` has to ask for it**, in step 5 beside ticking the steps, or no
  agent will maintain one. The instruction should say what makes an estimate
  worth having: revised when it changes rather than set once, and shortened *or*
  lengthened honestly — an item that says two hours for six hours running is
  worse than one that says nothing.

## The options, and what each costs

1. **The card reads the worktree's copy of the item. — chosen.** `BacklogRun` already
   carries `worktreePath` and `isPresent`, and a card is already built off the
   main thread by the code that walks the folder — so this is a second read in a
   place that is already doing file system work, and needs no new protocol and no
   second writer. The catch: the item may be in a *different folder* on the
   branch, because an agent that ran `done` has moved its copy to `completed/`.
   So it must be found by number rather than by path, which `Backlog` can already
   do. **This is the cheap one and probably the right one.**
2. **Read from the branch instead** — `git show <branch>:<path>`. Survives a
   worktree somebody deleted, at the cost of a git process per card on a board
   that redraws on every scroll. The worktree is the live thing anyway, and
   `isPresent` already says when it is gone.
3. **The agent writes progress back to the project's copy.** Rejected before
   anybody tries it: two writers to one file, a conflict at every merge, and it
   breaks the property the whole design rests on — that the file travels with the
   work.
4. **Do nothing, and fix the sentence.** Honest, cheap, and leaves the board
   answering a question nobody asked. Worth naming as the fallback if the reading
   turns out to be more expensive than it looks.

## Worth deciding

- **Say where the number came from.** A fraction from a branch that is three
  commits ahead of the project is not the same fact as one from the project, and
  a card that shows one as the other is how somebody comes to trust a number they
  should not. The card already draws the branch name; the fraction could sit
  beside it rather than pretending to be the item's own.
- **A worktree that has gone.** `isPresent` is false, and the project's copy is
  then all there is — which is right, and should be visibly the older number
  rather than silently it.
- **Cost.** A board redraws on every scroll and 0443 built the card struct
  precisely so that drawing costs nothing. Whatever this does must happen on the
  walk, not in `draw(_:)`.

## What it came to, and what was ruled out on the way

**Where the numbers come from.** `BacklogRun.itemInWorktree` finds the item in
the checkout by number, and `BacklogCard`'s initialiser — which already runs on
the walk, off the main thread — reads the checklist, the estimate, the pictures
and the delta off whichever copy it gets, falling back to the project's. Nothing
was added to `draw(_:)`. Cards with no run pay nothing: `itemInWorktree` touches
the disk only when a checkout was recorded for that number and is still there.

`Backlog.item(number:)` had to be made cheap first. It built every item in every
state and then looked for the number, which reads the head of four hundred and
fifty files; it now matches the directory listing and reads one. That was
invisible while nothing called it in a loop and would have been a stutter per
card.

**The card says "in the worktree", not the branch name.** The entry suggested
the fraction could sit beside the branch — `3/6 in backlog/0455-…` — and that
was tried and rejected on the layout: this line truncates at the tail, so a
branch name second would push the estimate, the image count and the spec mark
off every in-progress card on the board. That there *is* a worktree goes at the
head where it survives; which one goes at the tail where it can be lost, which
is where it already was.

**Three lines of marks, and both numbers were photographed rather than
reasoned about.** At one line the estimate came out as `a…`. At two it reached
`as of 07:…`, which loses the half of an estimate that matters. Three fits
`1/12 in the worktree · about an hour, as of 07:11 · backlog/0458-…` with only
the branch truncated. A card takes only the lines its marks need, so this is a
line taller for the four or five items being worked on and unchanged for the
rest of the board.

**`byTruncatingTail` means "this is one line".** With it on the paragraph style
the second line of the rect was reserved, paid for in card height, and left
empty while the first still ended in `a…`. `byWordWrapping` plus
`.truncatesLastVisibleLine` is the pair that wraps *and* ellipsises. That cost a
photograph to notice and would not have shown in any test this pane can have.

**`markLine` had to change how it measures.** It was `size(withAttributes:)`,
which is right for a single line placed by its baseline and wrong for a line in
a wrapped rect — the same "one font metric asked two ways" that this file's
comments already record from the last time.

### Ruled out

- **Computing the estimate.** Elapsed over ticked, times remaining. Rejected in
  the entry and worth repeating: it is most confident exactly when it is most
  wrong, and it would have to be believed because nothing else is on the card.
  Not built, not even as a fallback where nobody has written one.
- **A relative age on the card** — "said 25m ago", which is the friendlier
  phrasing. A card is built when the folder is walked and drawn for as long as
  nothing changes, so a relative age freezes at the walk: a board left open for
  three hours would go on saying `5m ago` all afternoon, which is the failure
  the timestamp exists to prevent, in the display meant to prevent it. The
  absolute time is a fact that does not rot. The command line prints the age,
  because a line of output is stamped when it is printed.
- **A staleness threshold** — greying an estimate older than an hour, or two.
  There is no defensible number, and printing the time it was said makes an old
  one look old without one.
- **The estimate in a header line or frontmatter.** A section beside `## Steps`,
  parsed the way `## Steps` is, keeps the item one document with no second
  syntax in it. `## Estimate` is in the template so that the question is
  visible; the prose under it does not parse, so a fresh item reads as having no
  estimate rather than a broken one.
- **A zone on the timestamp.** `2026-08-11 14:20`, local. More correct with an
  offset and less likely to be typed correctly by hand — and this is a claim
  about the next few hours, read on the machine the worktree is on. If backlogs
  ever move between machines this is the line that will have to change.
- **Dropping the branch name from the card** now that the fraction says there is
  a worktree. It would have freed the whole tail — the branch is `backlog/` plus
  the number and slug the card already shows — but 0445 put it there
  deliberately and nobody asked for it back.

### Not proved

- **No test covers the card.** `BacklogPane` is in the app target, which the
  suite cannot reach. What there is: `theProgressIsTheWorktreesAndTheStateIsThe
  Projects` in `BacklogRunnerTests` drives a real worktree, ticks two steps in
  it, runs the `completed/` move that `done` does, and asserts the branch says
  2 and the project says 0 — everything below the card. The card itself was
  photographed, and the menu asked with `--backlog-menu`.
- **The worktree that has gone was fabricated.** All four live checkouts existed
  today, so a run entry pointing at a directory that never existed was written
  into a private copy of `backlog-runs.json` and the board photographed over it:
  `12/14 in the project`, no branch drawn, and no worktree entries on the menu.
  Nothing was deleted to test it.
- **The `completed/` case that motivated finding an item by number cannot
  actually reach a card.** Found at the end, by photographing the board after
  running `done` on this very item: `done` moves the copy to `completed/` on the
  branch *and* forgets the run in the project, deliberately — "a run left in the
  project's list keeps the dashboard saying somebody is on it". So the card falls
  back to the project's copy in the same moment, and the fraction reverts. The
  by-number lookup is still the right one and still load-bearing, for the case
  `AGENTS.md` sends agents to when they are stuck: a copy moved to `waiting/` on
  the branch, with the run still recorded. The spec scenario was written for
  `completed/` and corrected to `waiting/` once this was seen. A requirement
  nothing implements is worse than no requirement.
- **The estimate's usefulness is one data point.** It was maintained on this
  item while this item was worked — set at two hours, revised to one — which is
  the cheapest possible test of whether the format is one anybody would keep,
  and not evidence that anybody else will.

## Steps

- [x] A card's progress comes from the worktree when there is one, found by
      number rather than by path
- [x] The image count and the spec delta come from the same place, for the same
      reason
- [x] Where the number came from is visible, so a branch's fraction is not
      mistaken for the project's — asked for explicitly, not inferred
- [x] "Reveal Worktree in Finder" on the card's menu, beside 0445's two, under
      the same `isPresent` guard
- [x] A worktree that has gone falls back to the project's copy, visibly
- [x] All of it on the walk, never in `draw(_:)`
- [x] An estimate, written by whoever is working the item, carrying when it was
      last said, and absent rather than guessed when nobody has said one
- [x] The card shows it beside the fraction, and shows a stale one as stale
- [x] `AGENTS.md` asks for the estimate in step 5, beside ticking the steps
- [x] `AGENTS.md`'s promise in step 5 becomes true, or goes
- [x] Write down here what was ruled out on the way
- [x] `spec/backlog.md` says what the project now does
