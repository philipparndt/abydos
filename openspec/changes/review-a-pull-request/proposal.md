# Review a pull request

## Why

Reviewing somebody's pull request means reading code, and this is a program for
reading code — but the review happens in a browser, where there is no language
server, no go-to-definition, no outline, no running the tests, and no way to
open the file the change is actually about. So a review of anything non-trivial
is done twice: once in the browser to see the diff and leave the comments, and
once here to understand what the diff does.

The half that is missing is not the diff viewer. **This app already reviews
changes**: `ChangesPane` and the commit page draw a tree of changed files with
their diffs, `ResultChecklist` already ticks items off a list and hides the done
ones, `GitWorktrees` already checks a branch out beside the project without
disturbing what is open, and the titlebar already switches between checkouts.
What is missing is a pull request: the list of them, whose branch it is, what
the base is, who has already said what, and a way to answer.

There is no originating `.abydos/backlog` item; the backlog was retired before
this was raised.

## What changes

**Pull requests are browsed in the app.** The open ones for this repository,
with title, author, branch, draft state and how far along the checks are. A
list rather than a wall: which ones are waiting on *you* is the question a
review list is opened to answer.

**A pull request opens as a page**, beside the log and commit pages it is a
sibling of — a tree of changed files with their diffs, arranged by folder or
flat, in the two arrangements the commit page already offers.

**Files are ticked as they are read**, through the same checklist the usages
list and the search results use: progress, hide-done, and a key that goes to
the next thing not yet read.

**A tick dies when the file it was about changes.** Ticks are recorded against
the head commit they were made on; when the author pushes, the ticks for files
whose diff moved are cleared and the rest are kept. A tick against a diff that
has since changed is not a record of having read it — it is a false one, and
the whole value of ticking is that the list can be trusted.

**The branch is checked out as a worktree**, so the project tree, the language
server and the tests are all pointed at the change under review while whatever
was being worked on stays where it was. Two pull requests can be open at once,
which is what happens on a day when somebody is blocked.

**Comments are read and written in the diff.** Existing review comments appear
against their lines, so a reviewer joins a conversation rather than starting a
second one; new comments are left on a line and a review is submitted as
approved, commenting or requesting changes.

**Through `gh`, not through a token this program stores.** The GitHub CLI is
already how everything else in this repository talks to GitHub, it is already
authenticated on the machines this runs on, it handles Enterprise hosts and SSO
and token refresh, and it means this program never holds a credential. A
missing or logged-out `gh` is reported as itself — the one thing an empty list
must never look like is a repository with no pull requests.

## Capabilities

### New Capabilities
- `pull-requests`: browsing the pull requests of a repository, opening one as a
  page of changed files and diffs, ticking files off as they are read against
  the commit they were read at, checking the branch out to read it in place,
  and reading and writing the review's comments and verdict.

### Modified Capabilities
- `usages`: the checklist grows a notion of what a tick was recorded *against*,
  so it can be invalidated rather than only set and cleared.
- `version-control`: a worktree may be made and later removed on a pull
  request's behalf, which is a checkout this program created rather than one
  somebody asked for by name.

## Impact

- New `Sources/AbydosKit/Forge/` for talking to `gh` and modelling a pull
  request, its files, its comments and its checks. No new dependency: `gh` is a
  process, like `git`.
- `GitForge` already parses the remote into host, owner and name; that is what
  says which repository to ask about, and it is reused rather than repeated.
- New `Sources/AbydosApp/Review/` for the list and the page. The page is built
  from what the commit page already is — `GitChangeTree`, the file outline, the
  diff view — rather than a second arrangement of the same thing.
- `ResultChecklist` gains invalidation; `usages` and `search` keep their present
  behaviour, which is the case where nothing is ever invalidated.
- `ProjectSession` remembers the ticks, per pull request, per head commit.
- The left rail gains a way in, and the driven-run flags gain a way to open a
  pull request, walk its files and read the report back.
- **Not in scope**: creating pull requests, merging them, and any forge that is
  not GitHub or an installation sharing its layout — `GitForge` already draws
  that line and this follows it.
