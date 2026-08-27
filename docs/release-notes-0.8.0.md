# Abydos 0.8.0

Eleven commits, and all of them are one thing: a pull request can be reviewed
here, from the list of them to the moment of saying approved or not.

Reviewing somebody's code means reading code, and this is a program for reading
code — but the review happened in a browser, where there is no language server,
no go-to-definition, no outline, no running the tests, and no way to open the
file the change is actually about. So a review of anything non-trivial was done
twice: once in the browser to see the diff and leave the remarks, and once here
to understand what the diff did.

The half that was missing was never the diff viewer. This app already reviews
changes. What was missing is a pull request: the list of them, whose branch it
is, what the base is, who has already said what, and a way to answer.

## The list, and what it answers

A pull request tool is opened to answer one question — **what is waiting on
me** — so the ones this account has been asked to review are marked and sorted
to the top, rather than mixed into a wall of rows that has to be read to find
them.

Every row says the number, the title, the author, the branch, whether it is a
draft and how far along its checks are. Those last two are there because a pull
request whose build is red is usually not worth reading line by line yet, and
that is a fact about the work rather than about the reviewer's taste.

Whether "waiting on me" includes a team you belong to is a switch above the
list rather than a rule. `user-review-requested:@me` and `review-requested:@me`
are two different questions, and which one a repository wants depends on how it
assigns its reviews — which cannot be worked out from here. Teams count by
default, because that is the setup where the narrow answer is silently empty
and somebody concludes nothing is waiting on them.

It has its own button on the rail, beside the git one rather than behind it.
What is behind the git button is one tree — the working copy, the stashes and
the refs, all things this repository holds. A pull request is none of those: it
is on somebody else's server, asked about over the network, and opened to read
somebody else's work.

**The list is asked for, never polled.** Every other git pane re-reads on each
filesystem event because git is local and cheap; this is a network call against
an API with a rate limit, so it asks when the pane opens and when the button
next to it is pressed.

## Reading one

A pull request opens as a page beside the log and the commit view, and it is
made of what those pages are made of: the same file outline, the same two
arrangements, the same line counts, the same keyboard. A second arrangement of
the same thing is how two lists come to disagree about what a rename looks
like.

**The files are the change against the point it branched from**, not the
difference between two tips. A file the base branch moved underneath the author
is not a file they touched, and listing it sends a reviewer to read somebody
else's work. Taking one open pull request against `cli/cli` as it stood: three
files changed, on a base that had gained 29 commits touching 17 files since it
branched.

**The diff can be the whole file.** A browser shows three lines either side of
a change; here the file is on disk with a language server pointed at it, and
the question a reviewer actually has is usually about the code *around* the
change. The hunks are spliced back into the file at the head — the changed
lines exactly as git wrote them, everything else as context — so the same view
draws it with the same colours and honest line numbers.

Nothing on this page stages anything. The diff view offers staging by line
because the changes pane needs it; on somebody else's branch those gestures are
meaningless, and a menu item that cannot work is worse than none.

## Ticking files off, and ticks that die

Files are ticked as they are read, through the same checklist the usages list
and the search results use: progress, hide-done, and one key to the next thing
not yet read. A reviewer's place in a long list is the thing most easily lost
and the most annoying to find again. The ticks are remembered per pull request
and outlive the window.

**A tick dies when the file it was about changes.** Ticks are recorded against
that file's diff at the head they were made on; when the author pushes, the
ticks for files whose diff moved are cleared and the rest are kept.

The token is the diff and not the head commit, and that choice is the whole
feature. A rebase that changed nothing keeps its ticks — the case a reviewer
meets most often and would resent losing — and a force-push that *did* rewrite
one file clears exactly that one, without either being a special case. Clearing
everything on every push would be as bad in the other direction: a pull request
pushed to five times during a review could then never be finished, and the
reviewer would learn to ignore the ticks.

A tick against a diff that has since changed is not a record of having read
something. It is a false one, and the whole value of a checklist is that it can
be trusted.

## Reading it in place

The branch can be checked out as a worktree beside the project, so the language
server, go-to-definition, the outline and the tests are all pointed at the
change under review while whatever was being worked on stays where it was. Two
pull requests can be open at once, which is what a blocked morning looks like.

It is a switch rather than a door: the page does not move when it is pressed —
not the file you were reading, not your place in it, not what you had ticked or
written. Pointing the window at the checkout is a separate thing to want, and
it is in the list's own menu.

A checkout made for a review says so, in the branches pane and in the titlebar
menu. The list of checkouts is a list of places somebody chose to work; one
made to read somebody else's branch is temporary and belongs to a review, and a
reviewer who opens three a day otherwise grows a checkout a day, each named
after a stranger's branch. Finishing with one removes it, and one holding
changes refuses and says what is in it.

## The conversation, and answering

The remarks already on a pull request are drawn on the diff, at the lines they
were left on, with who left them and when. A reviewer who cannot see them says
again what somebody has already said, which is worse than saying nothing: the
author now has two conversations about one line.

**A remark whose line has gone is shown, not dropped.** GitHub calls those
outdated; they are kept against their file and marked as being about an earlier
version, because a conversation that happened is worth knowing about even when
the code it was about is not there any more.

Remarks are written on a line or a run of lines — pointing at the first line of
a five-line mistake makes the author find the other four — and go in **one
submission** with a verdict of approved, commenting or requesting changes. That
is how GitHub models it and how a reviewer thinks: a review is a set of remarks
and a verdict, not a series of interruptions to the author.

The head the page was read at travels with the review. If the author has pushed
since, the line numbers mean something else, and that is said before anything is
sent — a remark that lands on the wrong line is a remark about somebody else's
code, sent in the reviewer's name. What is written stays written until the
submission succeeds; the failure that matters is a review that looks sent and is
not, because the author is waiting on it.

## Through `gh`, and never a token this program holds

Every request goes through the GitHub CLI. It is already how the rest of this
repository talks to GitHub, it is already authenticated on the machines this
runs on, it handles Enterprise hosts and SSO and token refresh, and it is a
process — like `git` — so it costs no dependency. A token kept here would be a
second place for a credential to leak from and a second thing to expire without
saying so.

The cost of that is real and is stated rather than hidden. A missing `gh`, a
`gh` that is not logged in, and a remote that is not a forge this understands
are three first-class answers, each saying what to do about it:

    The GitHub CLI is not logged in to ghe.example.com.
    Log in with `gh auth login --hostname ghe.example.com`.

**None of them may render as an empty list.** "No pull requests are open" is a
sentence about the repository and "the CLI is not logged in" is a sentence about
the machine; a reader cannot tell them apart from a blank pane, and only one of
them is something they can act on.

## Every diff in the app

Two of these are about diffs generally rather than about reviewing, so they are
items in the View menu and the commit page and the log page get them too.

**Git's preamble is not drawn.** `diff --git`, `index` and the two `---`/`+++`
lines say which file this is, and every pane that shows a diff has just said
that — there is a tree beside it with one row selected. On a five-line change
that was the top half of the pane explaining itself. What is kept is the text
after the `@@`, git's guess at the declaration the hunk is inside, drawn on its
own as a labelled rule: the one part of the preamble the rest of the window does
not already say. The commit page's diff of a one-line change went from eight
rows to three.

**The two sides can be drawn beside each other.** A run of removals is paired
with the run of additions that follows it, which is what makes a rewritten block
readable — the old line and the line that replaced it on one row, and a run
longer on one side padded with a shaded absence.

## Under the hood

The commit page's changed-file list is a view of its own now, so the pull
request page hosts the same one rather than a second one that would drift. The
checklist behind the ticks is shared with the search results and the usages
list, which pass no token and are unchanged by it.

Both extractions were proved to be moves rather than rewrites the same way:
drive the app before and after and compare the reports line for line. Both were
identical, which is the only reason either was safe to make.

## Known

Submitting a review is exercised against everything except a live send. The
payload, the head-moved warning, the failure path and the remarks surviving a
failure are all checked; the last step — a review submitted to a real pull
request and read back — needs a scratch repository on somebody's GitHub account
and has not been run.
