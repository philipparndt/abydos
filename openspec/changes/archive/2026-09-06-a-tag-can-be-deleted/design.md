## Context

`GitTags` has held both halves since the moving-tag work: `delete` runs
`git tag --delete`, and `deleteOnRemote` runs
`git push --delete origin refs/tags/<name>` with the terminal prompts shut off,
fully qualified because `git push origin :v1` is ambiguous when a branch of
that name exists. Neither is called from anywhere in the app.

What the app does have is the shape of the question. `BranchDeletion` is one
object per press, holding what was true when the press happened, with a comment
recording why it holds itself while its sheet is up: `ask` returns the moment
the sheet is on screen, the caller lets the object go, and the completion
handler then found `self` nil and did nothing at all — no error, because
nothing ran to fail. `recreateTag` in `BranchesPane` is the tag-shaped version
of the same modal flow, weak from the top for the same reason.

The refs tree already knows which rows are tags (`branch.kind == .tag`), and
already has the two places a tag row's verbs are reached from: the row's
context menu and the keyboard action on the row.

## Goals / Non-Goals

**Goals:**

- The tag rows offer the delete the engine has always been able to do, for one
  tag or several.
- The remote is a separate, named agreement, because it is a different
  consequence with a different audience.
- What failed, and which half of it, is said in the words of the half that
  failed.

**Non-Goals:**

- Not touching `BranchDeletion`: a branch delete asks about worktrees and
  merged-ness, a tag delete asks about a remote, and folding them together
  would make one object that answers in two vocabularies.
- Not deleting releases or anything else on the forge — a GitHub release
  survives its tag's deletion, and pretending otherwise in a sheet would be
  worse than saying nothing.
- Not asking the network what tags the remote has before the sheet opens.
- Not adding an undo: git has none for this, and an offer to put a tag back
  that quietly re-pushed would be the more dangerous button.

## Decisions

### A sibling type, not a mode

`TagDeletion` mirrors `BranchDeletion`'s lifetime and sheet handling and
nothing else. It takes the tags, the root, the remote name and the window;
it asks; it runs the two verbs in order; it reports. The one thing it copies
deliberately is the self-holding, and the comment says which bug that is
for rather than repeating the explanation.

*Ruled out:* a second `kind` on `BranchDeletion` — the file is 886 lines of
branch-and-worktree reasoning, and every sentence in its sheet would have
needed an "unless this is a tag".

### The remote is a checkbox, off, and named after the remote

The sheet says *Also delete on `origin`* — the remote's own name, since a fork
and an upstream are both plausible and a sheet saying "the remote" would be
asking somebody to remember which. It is off by default: the local delete is
recoverable from any commit that still exists, and the remote one is what
other people's fetches and a workflow's `actions/checkout` read.

Where the repository has no remote, the row is not shown at all rather than
shown disabled: there is nothing to explain.

*Ruled out:* deciding for somebody by asking `git ls-remote --tags` first — a
network call before a sheet opens is a sheet that hangs on a slow connection,
and the answer would be stale by the time it was agreed to. The delete on the
remote of a tag that is not there is `git push --delete` returning "remote ref
does not exist", which the report can say plainly.

### The two halves are run in that order, and reported separately

Local first: it is the one that always works, and if the remote half fails the
tag is at least gone from the tree the person is looking at. The report names
what happened to each — *deleted here, still on `origin`* — because "could not
delete" over a half-done pair is the sentence that sends somebody to the
command line to find out what state they are in.

*Ruled out:* remote first with a local rollback. There is nothing to roll back
to that is worth the complexity: a local tag can be written again from the
commit it pointed at, which the report names.

### Several tags at once, and only tags

The selection rule follows `deletableBranches`: the delete acts on the selected
rows that are tags, and is offered only when every selected row is one. A mixed
selection of a branch and a tag is two different questions with two different
sheets, and the menu offering one of them would act on half the selection.

## Risks / Trade-offs

- [Deleting a tag a release is attached to] → the sheet says the release
  survives the tag on GitHub and that the tag is what a workflow reads; it does
  not offer to touch the release.
- [A protected tag on the remote refuses] → that is the remote-half failure the
  report is written for, and the local half stands.
- [A driven run that deletes on a real remote] → the run's remote is a bare
  repository made under the scratchpad and set as `origin`; nothing in the
  proof reaches anybody else's machine.
- [Several tags, one of which fails on the remote] → each is reported by name;
  the run does not stop at the first failure, since the others are independent.

## Open Questions

None: the engine's verbs are written, the sheet's shape is `BranchDeletion`'s,
and the remote's name is the repository's own.
