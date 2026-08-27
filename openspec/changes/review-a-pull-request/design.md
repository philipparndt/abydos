## Context

Most of this exists. The parts that are new are the forge and the invalidation;
the rest is arrangement of things that already work, and the design is mostly
about not building second versions of them.

What is already here:

| | what it gives |
|---|---|
| `GitForge` | a remote turned into host, owner, name; URLs for a branch, a commit, a file at a line |
| `GitChangeTree` / `GitChangeNode` | changed files as a folder tree, with counts and partial states |
| the commit page (`HistoryPane`) | a file outline, two arrangements, a diff per file, line counts |
| `DiffView` | a diff drawn, with per-line selection — already used for staging by line |
| `ResultChecklist` | ticks, ␣ and ⌫, undo, progress, hide-done, ↓ shows the row |
| `GitWorktrees` | add, remove, list, ordered by recent activity; the titlebar switches between them |
| `ProjectSession` | per-project state that survives closing the window |

What is not here: anything that talks to a forge, and any notion of a tick being
about a particular version of a thing.

## Goals / Non-Goals

**Goals:**

- Read a pull request without leaving the app, and finish it — comment, and say
  approved or not.
- Reuse the commit page's tree, outline and diff rather than build a second one.
- A checklist whose ticks can be trusted after the author pushes.
- No credential in this program.

**Non-Goals:**

- Creating or merging pull requests. Reviewing is a job; those are two others.
- Forges other than GitHub and installations sharing its layout. `GitForge`
  already draws that line for links, and this follows it rather than widening it.
- A general GitHub client — issues, releases, actions. The unit here is the
  review.
- Offline review. `gh` needs the network, and a cached pull request that is
  quietly out of date is the invalidation problem again in a worse place.

## Decisions

### `gh` as the transport, run like `git`

`GitRepository.runSync` is already the shape: a `Process`, both pipes drained,
an exit code and two strings. `gh` gets the same treatment in a new
`Sources/AbydosKit/Forge/`, asking for JSON — `gh pr list --json`,
`gh pr view --json`, `gh pr diff`, `gh api` for review comments — and decoding
it into types of this repository's own.

*Alternative considered:* the REST API with a token in the Keychain. Rejected —
it is a credential this program would then own, a token to refresh, an SSO
dance to implement per Enterprise host, and a dependency or a hand-rolled HTTP
client. `gh` is a process, and this repository already has the machinery for
running processes and the habit of preferring one to a library.

*Consequence, stated because it is a real cost:* `gh` must be installed and
logged in, and this program cannot fix either. So both are first-class answers
rather than errors — the spec's second and third scenarios — and neither ever
renders as an empty list.

### The page is the commit page, given a different source of files

A pull request page and a commit page are the same view of the same thing: a
list of changed files, arranged by folder or flat, a diff each, line counts, a
keyboard that walks them. The difference is where the files come from and what
can be done to a row.

So the page is built by extracting what the commit page already does into
something both use, rather than by copying it. That extraction is the risky part
of this change and it is deliberately first in the task list, with the commit
page's own driven checks run before and after to show it still behaves.

*Alternative considered:* a separate review page written from scratch. Rejected
for the reason the file-length rule exists: two lists of changed files, drifting
apart, is how the second one comes to be the one nobody exercises — and the
commit page's own comment says exactly this about outlines and tables.

### A tick carries a token, and the checklist knows nothing about pull requests

`ResultChecklist` gains an optional token per row and a `revalidate` that clears
the ticks whose token has changed. It does not learn what a commit is.

For a pull request the token is the hash of that file's diff at the head it was
ticked at. Using the diff and not the head commit is what makes a rebase that
changed nothing keep its ticks — the case a reviewer meets most often and would
resent losing — and what makes a force-push that *did* change a file clear it,
without either being a special case.

*Alternative considered:* the head SHA alone as the token for every row. Simpler
and wrong in the common direction: every push clears everything, so a pull
request pushed to five times during a review can never be finished, and the
reviewer learns to ignore the ticks.

*Alternative considered:* per-row content hashes computed here from the file.
Rejected — the diff is what was read, not the file; a file can differ between
base and head for reasons the diff does not show.

### The worktree is made by this program and says so

`GitWorktrees.add` already exists. What is new is a mark saying a checkout
belongs to a pull request, so that the checkout list can distinguish it and so
that three reviews a day do not silently become three checkouts a day.

The mark lives with the project's own state rather than in git: it is this
program's opinion about a directory, not a fact about the repository, and
writing it into `.git` would be writing somebody else's file.

### Comments are read at the head, and shown even when their line has gone

A review comment names a file, a commit and a position in a diff. When the head
moves, some comments no longer have a line. GitHub calls these outdated and so
does this: they are shown against the file with what they were about, rather
than dropped — a reviewer needs to know a conversation happened even when the
code it was about is gone.

Writing a comment posts against the current head, which is the only position
that can be resolved.

### Submitting is one act, and it says whether it happened

Comments written on a page accumulate as a pending review and go in one
submission, which is how GitHub models it and how a reviewer thinks: a review is
a set of remarks and a verdict, not a series of interruptions to the author.

The submission's outcome is reported. What is written stays written until the
submission succeeds — the failure that matters is a review that looks sent and
is not, because the author is waiting on it.

## Risks / Trade-offs

**Extracting the shared file-list out of the commit page breaks the commit
page.** → It is the first task, done on its own, with `--log-page` and
`--commit-page` driven before and after and the reports compared. Nothing about
pull requests is written until that is green.

**`gh`'s JSON is a contract this does not own.** → Decoding is in one place, per
command, and a field that is missing degrades that row rather than failing the
list. The `gh` version is reported in the driven output, so a change in its
output is diagnosable rather than mysterious.

**Rate limits and slow calls.** → Every call is off the main thread through the
same path `git` uses, the list is fetched once per open rather than polled, and
a refresh is something somebody asks for.

**Worktrees accumulate on disk.** → They are marked, listed and removable, and
removal obeys the existing refusal on a checkout holding changes. The house has
already lost 4.9 GB to an orphaned worktree once, which is why this is a risk
worth writing down rather than a tidiness point.

**A review submitted against the wrong head.** → The head the page was opened at
is carried with the pending review; if the head has moved at submission time,
that is said before anything is sent.

**Scope.** This is the largest single change proposed here since the window
controller split, and it has four parts that could each ship alone: the list,
the page, the checkout, the writing. The task groups are ordered so that each is
usable on its own — browsing and reading is worth having before commenting
exists.

## Migration Plan

Nothing to migrate: no stored format changes except `ProjectSession` gaining a
field, which is additive and absent on every session written before this.

Each group is a commit, green on `make test` and `make warnings`.

## Open Questions

- Whether the pull request list belongs on the left rail beside the branches and
  history tools, or in the project switcher's popover where branches already
  are. The rail is the assumption; it is cheap to move once there is something
  to look at. --> left rail as separate item for now
- Whether "waiting on me" should include pull requests where this account is on
  a requested *team* rather than named. `gh` can answer it; whether it is wanted
  depends on how the teams are set up, and that is a question for a repository
  with teams rather than for this one. --> a switch "only me" "teams where I am in"
- Whether the diff should offer the staging gestures `DiffView` already has.
  They are meaningless on somebody else's branch, and the same view is used for
  both — so either the gestures are conditional or the view is told which tense
  it is in. Deferred to the task that reuses it, when the shape is in front of
  somebody. --> should not be offered but the diff should have the option to show the diff in the complete file and not only parts of the file. This is where the local review can play its advantages the most, having a lsp that helps navigating, ...
