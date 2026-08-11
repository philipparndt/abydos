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

## Steps

- [ ] A card's progress comes from the worktree when there is one, found by
      number rather than by path
- [ ] The image count and the spec delta come from the same place, for the same
      reason
- [ ] Where the number came from is visible, so a branch's fraction is not
      mistaken for the project's — asked for explicitly, not inferred
- [ ] "Reveal Worktree in Finder" on the card's menu, beside 0445's two, under
      the same `isPresent` guard
- [ ] A worktree that has gone falls back to the project's copy, visibly
- [ ] All of it on the walk, never in `draw(_:)`
- [ ] `AGENTS.md`'s promise in step 5 becomes true, or goes
- [ ] Write down here what was ruled out on the way
- [ ] `spec/backlog.md` says what the project now does
