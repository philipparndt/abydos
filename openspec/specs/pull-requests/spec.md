# Pull requests

## Purpose

Reviewing a pull request where the code is: the list of what waits on the reader, the page a pull request opens as, ticks that remember what was read and die when it changes, and the worktree checkout that lets the change be read in place.

## Requirements

### Requirement: GitHub is reached through `gh`, and never through a credential this program holds

Every request to a forge SHALL be made by running the GitHub CLI, and this
program SHALL NOT store, prompt for, or read a token of its own.

`gh` is already how the rest of this repository talks to GitHub. It is
authenticated once, per machine, by the person who owns the account; it knows
about Enterprise hosts, SSO and token refresh; and it is a process, like `git`,
so this costs no dependency. A token kept here would be a second place for a
credential to leak from and a second thing to expire without saying so.

Which repository to ask about SHALL come from `GitForge.repository(in:)`, which
already turns a remote into a host, an owner and a name.

**A missing or logged-out `gh` SHALL be said, not shown as emptiness.** The one
thing this must never look like is a repository with no pull requests open,
because that is a sentence about the repository and this is a sentence about
the machine. The two are not distinguishable by a reader and only one of them
is actionable.

#### Scenario: gh is installed and logged in

- **GIVEN** a project whose `origin` is a GitHub repository
- **WHEN** the pull requests are asked for
- **THEN** the open ones are listed

#### Scenario: gh is not installed

- **GIVEN** a machine with no `gh` on the path
- **WHEN** the pull requests are asked for
- **THEN** the list says the GitHub CLI is not installed, and how to install it

#### Scenario: gh is installed but not logged in

- **GIVEN** `gh` present and `gh auth status` failing
- **WHEN** the pull requests are asked for
- **THEN** the list says the CLI is not logged in, and names the command that
  logs it in

#### Scenario: a remote that is not a forge this understands

- **GIVEN** a project whose `origin` is a plain path or an unknown host
- **WHEN** the pull requests are asked for
- **THEN** the list says this repository has no GitHub remote, rather than
  showing nothing

### Requirement: The list says which pull requests are waiting on the reader

Open pull requests SHALL be listed with their number, title, author, source
branch, draft state, and the state of their checks.

A review list is opened to answer one question — what is waiting on me — so the
ones this account has been asked to review SHALL be distinguishable from the
rest without reading every row.

Checks are shown because a pull request whose build is red is usually not worth
reading line by line yet, and that is a fact about the work rather than about
the reviewer's taste. Draft is shown for the same reason.

#### Scenario: pull requests awaiting this reviewer

- **GIVEN** a repository with several open pull requests, two of which request
  this account's review
- **WHEN** the list is shown
- **THEN** those two are marked as waiting on the reader

#### Scenario: a draft with failing checks

- **GIVEN** an open pull request that is a draft and whose checks have failed
- **WHEN** the list is shown
- **THEN** the row says both

### Requirement: A pull request opens as a page of changed files and diffs

Opening one SHALL open a page in the editor area holding the files it changes
and the diff of each, arranged by folder or flat.

It is a page and not a panel for the reason the log and the commit view are
pages: a diff is read, and a third of a window is not for reading. It is built
from what those pages are made of — the change tree, the file outline, the diff
view — rather than a second arrangement of the same thing, so that the two
arrangements, the line counts and the keyboard all behave as they already do.

The diff SHALL be the change the pull request makes against the point it
branched from, and not the difference between two tips: a file that the base
branch changed underneath the pull request is not a file the author touched, and
listing it makes a reviewer read somebody else's work.

#### Scenario: opening one

- **GIVEN** a pull request that changes four files in two folders
- **WHEN** it is opened
- **THEN** a page shows those four files, arranged by folder, with a diff each

#### Scenario: the base moved on

- **GIVEN** a pull request whose base branch has had unrelated commits since it
  was opened
- **WHEN** it is opened
- **THEN** only the files the pull request itself changes are listed

### Requirement: A file is ticked as it is read, and the tick says which commit it was read at

Each changed file SHALL be tickable, the ticks SHALL be remembered per pull
request, and each tick SHALL record the head commit it was made against.

This is the checklist the usages list and the search results already are —
progress, hide-done, and one key to the next thing not yet read. A reviewer's
place in a long list is the thing most easily lost and the most annoying to
find again.

#### Scenario: ticking a file

- **GIVEN** a pull request page with four files
- **WHEN** two are ticked
- **THEN** the page says two of four, and hiding the done ones leaves two

#### Scenario: coming back to it

- **GIVEN** a pull request with two of four files ticked, closed and reopened
- **WHEN** the page is opened again
- **THEN** the same two are ticked

### Requirement: A tick dies when the file it was about changes

A tick SHALL be cleared when the head moves and its file's diff moved with it,
and SHALL be kept when the file's diff is the same at the new head as it was at
the old one.

**A tick against a diff that has since changed is a false record**, and the only
value a checklist has is that it can be trusted. Keeping it would tell a
reviewer they had read something nobody has read. Clearing all of them on every
push would be as bad in the other direction: a pull request that is pushed to
five times while it is being reviewed would never be finished.

A force-push SHALL be treated the same way as any other move of the head. What
decides is whether the file's diff differs, not how the head came to move.

#### Scenario: the author pushes a change to one file

- **GIVEN** a pull request with four files, all ticked
- **WHEN** the author pushes a commit touching one of them
- **THEN** that file's tick is cleared and the other three are kept

#### Scenario: the author force-pushes a rebase that changes nothing

- **GIVEN** a pull request with four files, all ticked, rebased onto a newer
  base without conflict
- **WHEN** the page is opened again
- **THEN** the ticks are kept, because no file's diff differs

#### Scenario: a file added by the push

- **GIVEN** a pull request whose files were all ticked
- **WHEN** the author pushes a commit adding a fifth file
- **THEN** the fifth is present and unticked, and the four are kept

### Requirement: The branch is checked out as a worktree, so the change can be read in place

A pull request SHALL be openable as a worktree beside the project, and that
worktree SHALL be removable from the same place.

This is most of why a review belongs in an editor rather than a browser: the
language server, go-to-definition, the outline and the tests all need the code
on disk. A worktree rather than a checkout in place because a review arrives
while something else is half-done — the branch must not move under it — and
because two pull requests being open at once is what a blocked morning looks
like.

The worktree SHALL be one this program made and SHALL say so, so that the list
of checkouts distinguishes it from one somebody created by name.

#### Scenario: reading a pull request in place

- **GIVEN** an open pull request and a project with uncommitted work
- **WHEN** the pull request's branch is checked out
- **THEN** a worktree holds it, the original checkout is untouched, and the
  project tree can be pointed at either

#### Scenario: finishing with it

- **GIVEN** a worktree made for a pull request
- **WHEN** it is finished with
- **THEN** it can be removed from the same place it was made, and a worktree
  holding changes refuses rather than discarding them

### Requirement: The comments already on a pull request are shown against their lines

Review comments SHALL be shown at the lines they were left on, with their
author, and a comment on a line that has since moved SHALL still be findable.

A reviewer who cannot see the existing comments reviews what somebody has
already reviewed and says it again, which is worse than saying nothing: the
author now has two conversations about one line.

#### Scenario: a line somebody has commented on

- **GIVEN** a pull request with a review comment on a line of a file
- **WHEN** that file's diff is opened
- **THEN** the comment is shown against that line, with who left it

#### Scenario: a comment on a line the author has since changed

- **GIVEN** a comment left on a line that a later push moved or deleted
- **WHEN** the file is opened at the new head
- **THEN** the comment is still shown, marked as being about an earlier version

### Requirement: A review is written and submitted from the page

A comment SHALL be leavable on a line of a diff, and a review SHALL be
submittable as approved, commenting, or requesting changes.

Without this the app is a viewer: everything up to the moment of saying
something happens here, and then the reviewer opens a browser, finds the pull
request again, and finds the line again. The point at which a review is finished
is the point at which it is worth doing here at all.

Submitting SHALL say what happened. A review that failed to send and looks sent
is the worst outcome available, because the author is waiting on it.

#### Scenario: a comment on a line

- **GIVEN** an open pull request page
- **WHEN** a comment is written against a line and the review submitted as
  requesting changes
- **THEN** GitHub has that comment on that line, and the review is recorded as
  requesting changes

#### Scenario: approving without comments

- **GIVEN** an open pull request page with nothing written
- **WHEN** it is approved
- **THEN** the review is recorded as an approval

#### Scenario: the submission fails

- **GIVEN** a review written while the network is down
- **WHEN** it is submitted
- **THEN** it says it did not send, and what was written is still there
