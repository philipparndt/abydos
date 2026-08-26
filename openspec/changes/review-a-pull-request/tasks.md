## 1. Share the commit page's file list before anything is built on it

- [x] 1.1 Pull the changed-file list out of `HistoryPane` — the outline, the two
      arrangements, the line counts, the keyboard, the selection held by path —
      into something a second page can host
- [x] 1.2 The commit page uses it, and nothing about it changes: same rows, same
      arrangement, same `*` and same selection across a rebuild
- [x] 1.3 Drive `--log-page` and `--commit-page` before and after and compare the
      reports line for line; this is the check that the extraction was a move
- [x] 1.4 `make test` and `make warnings` green, and the recorded lengths updated

## 2. Talking to GitHub

- [ ] 2.1 New `Sources/AbydosKit/Forge/GitHubCLI.swift`: run `gh` the way
      `GitRepository` runs `git` — a process, both pipes drained, exit code and
      output — with the `gh` version reported for a driven run
- [ ] 2.2 Three answers that are not errors: no `gh` on the path, `gh` not
      logged in, and a remote that is not a forge this understands. Each says
      what to do about it
- [ ] 2.3 `PullRequest`, `PullRequestFile`, `ReviewComment`, `ChecksState` —
      decoded from `gh --json`, one decoder per command, a missing field
      degrading its row rather than failing the list
- [ ] 2.4 Tests over recorded `gh` output for every decoder, including a payload
      with fields missing and one from an Enterprise host
- [ ] 2.5 `GitForge.repository(in:)` says which repository to ask about; nothing
      here re-parses a remote

## 3. Browsing them

- [ ] 3.1 A list of open pull requests: number, title, author, branch, draft,
      checks
- [ ] 3.2 The ones requesting this account's review are marked, without having
      to read every row
- [ ] 3.3 A way in from the left rail, and a refresh that somebody asks for
      rather than a poll
- [ ] 3.4 The three non-error answers from 2.2 render as themselves in the list
- [ ] 3.5 Driven: a flag that lists them and prints what each row says

## 4. Reading one

- [ ] 4.1 A pull request opens as a page, using the shared list from group 1
- [ ] 4.2 The files are the change against the merge base, not the difference
      between two tips — a file the base moved is not in the list
- [ ] 4.3 A diff per file, through `DiffView`; answer the design's open question
      about the staging gestures on somebody else's branch
- [ ] 4.4 Driven: open a pull request, walk the files with the arrows, print the
      rows and the diff of one

## 5. Ticking, and ticks that die

- [ ] 5.1 `ResultChecklist` takes an optional token per row and gains
      `revalidate`, clearing the ticks whose token changed and keeping the rest
- [ ] 5.2 The usages list and the search results pass no token and behave
      exactly as they do today — driven, before and after, same output
- [ ] 5.3 The pull request page ticks files, with the token being that file's
      diff at the head it was ticked at
- [ ] 5.4 Ticks are remembered per pull request in `ProjectSession` and come
      back when the page is reopened
- [ ] 5.5 One key to the next file not yet ticked, and a count of what is left
- [ ] 5.6 Driven, the three cases that matter: a push touching one file clears
      one tick; a rebase that changes no diff clears none; a push adding a file
      leaves the existing ticks alone

## 6. Reading it in place

- [ ] 6.1 Check the branch out as a worktree through `GitWorktrees.add`, marked
      as belonging to this pull request
- [ ] 6.2 The mark is this program's state, not written into `.git`
- [ ] 6.3 The checkout list shows which ones are a pull request's, and the
      titlebar switches to them as it does to any other
- [ ] 6.4 Finishing with one removes it, and one holding changes refuses and
      says what is in it
- [ ] 6.5 Driven: check one out, confirm the project tree and the language
      server are pointed at it, remove it, confirm the list is shorter

## 7. The conversation already on it

- [ ] 7.1 Fetch the review comments and show them at their lines, with author
      and time
- [ ] 7.2 A comment whose line has gone is shown against its file, marked as
      being about an earlier version, rather than dropped
- [ ] 7.3 Driven: a pull request with a comment on a line, and one whose line a
      later push removed

## 8. Answering

- [ ] 8.1 A comment written on a line of a diff, held as part of a pending
      review rather than sent one at a time
- [ ] 8.2 Submit as approved, commenting, or requesting changes
- [ ] 8.3 The head the page was opened at travels with the pending review; a
      head that has moved by submission time is said before anything is sent
- [ ] 8.4 A submission that fails says so and leaves what was written where it
      is — the failure that matters is one that looks like success
- [ ] 8.5 Driven, against a real pull request on a scratch repository: leave a
      comment, submit, read it back

## 9. Proving it

- [ ] 9.1 `make test` and `make warnings` green
- [ ] 9.2 The commit page and the log page are unchanged — the reports from 1.3
      still match
- [ ] 9.3 The usages list and the search results are unchanged — the driven
      output from 5.2 still matches
- [ ] 9.4 No worktree is left behind by the driven runs, and
      `git worktree list` names none this change made
