## Context

A switch runs `MainWindowController.switchProject(to:…)`
(`MainWindowController+Terminal.swift:335`, body `:354`): it captures the
outgoing project into a `ProjectSession` — editor tabs, terminals, panel, tmux
window, subproject, run configuration, breakpoints, review ticks — stores it
both in memory (`ProjectSessions`) and on disk (`SessionStore.write`, which is
`.abydos/session.json`), reads the incoming project's session, calls
`load(project:)`, and finishes with `editor.restore(previous)`.

Two facts shape everything below.

**Pages are excluded from the capture on purpose.**
`EditorViewController.captureSession()` (`:4015`) keeps `tabs.filter {
$0.pageTitle == nil }`. Restore begins with `closeAllTabs()`, and a tab's
`contentView` is a page's only strong owner, so every git page is released
there; the sidebar's handles on them are weak (`logPage`, `commitPage`,
`stashPage`).

**The composed message exists only on screen.** `ChangesPane.subjectField` and
`bodyView` are private, there is no getter for the pair, and `root` is a `let` —
a pane cannot be re-pointed at another repository, which is why
`SidebarController.install(tool:force:)` rebuilds it and why the message dies
with the old instance. The one existing hand-off, sidebar to commit page, already
loses the description: `onOpenPage: ((String) -> Void)` carries a summary only.

## Goals / Non-Goals

**Goals:**

- The typed message survives a switch, a return, and the sidebar rebuild that
  follows `readGit()`.
- The pages come back on what they were showing.
- Nothing new is invented for storage: the session file the project already has.

**Non-Goals:**

- No cross-window merge. Two windows on one project already race over the
  session file; `rememberOpenEditors` merges rather than clobbers, and this
  change follows that and no further.
- No autosave-as-you-type into the file. The capture happens where every other
  capture happens — on the way out — plus at the one asynchronous rebuild that
  is known to eat the field.
- No restoring a page into a project that never opened one, and no opening the
  changes pane because a message exists: a restored message waits in the pane
  it belongs to.
- Not the split-window gap: `EditorAreaController.restore` only restores the
  active group, so a non-active group keeps the *previous* project's tabs. It is
  a real bug, it is not this one, and fixing it here would hide it.

## Decisions

### The message is a value in the session, not a per-repository default

`ProjectSession` already carries per-project text that outlives a window, and
`SessionStore` writes it beside the project. A `UserDefaults` key per repository
(the `RememberedChoice` shape) was ruled out: a half-written commit message is
project state, not a preference, and it belongs in the file somebody can delete
along with the rest of `.abydos`.

Both fields, or neither. The description is where the *why* goes and is the
expensive half; carrying only the summary is the bug the existing hand-off has.

### A page is described by its identifier plus what it is showing

`log` needs its ref and its path scope; `commit` needs nothing but itself, since
the message is carried separately; `stash` needs which stash, **by commit**
— `stash@{0}` names a different commit after one `git stash push`, so an index
would reopen the page on somebody else's work; `estate`, `launch` and `settings`
are their identifiers alone.

Ruled out: serialising the page objects. They are views over a repository that
may have moved on; re-opening through the existing openers means a returning page
reads the repository as it is now, which is what somebody coming back wants.

### Restored after the repository is ready, through the openers that already exist

Every opener guards on `project.git != nil` and would silently no-op during the
second or two a window takes to read the repository — so the reopen goes through
the existing `installWhenRepositoryIsReady` wait. The openers are also
idempotent: each reuses `group.page(identifier:)` when a tab is already there, so
a restore that races a person clicking cannot produce two log pages.

### The message is re-applied where the pane is built, not once after the switch

The sidebar's changes pane is rebuilt by `readGit()` after the switch has
finished, so a single re-application straight after `load(project:)` is undone a
moment later. The re-apply therefore belongs where a pane comes into existence
(`install(tool:force:)` / `makeToolView(.changes)`) and reads the session, rather
than being pushed at whatever pane happens to exist at the time.

That also fixes the loss the existing comment describes, which has nothing to do
with switching projects: a window opening onto a different work tree ate the
field too.

### Restoring is silent, and never overwrites something typed since

A restored message goes in only where the field is empty, which is the rule the
draft already follows: somebody who started typing in the new pane has said
something more recent than the file has.

### What a driven run can prove, and what it cannot

A driven run neither reads nor writes a session file — that is a requirement of
its own, so that a harness cannot walk over somebody's project. The switch path
does not need it: `ProjectSessions` keeps the outgoing session in memory keyed by
root, so leaving a project and returning inside one run exercises the capture and
the restore end to end. The file itself is proven by kit tests on `SessionStore`
instead, including an older file that lacks both keys.

## Risks / Trade-offs

- [A stale message restored weeks later] → it is the message for that project's
  working copy and it stays until committed or cleared; the commit that consumes
  it clears it, as it does today.
- [A message in the session file, in a repository] → `.abydos/session.json` is
  the file this state already lives in and is gitignored where it matters; a
  commit message is not a secret, and secrets in one are the user's own risk in
  the field as much as in the file.
- [Reopening several pages makes a return slower] → they are reopened after the
  repository is read, which is when a person can act anyway; each opener is the
  one a click uses.
- [Two windows on one project] → last write wins per field, as it already does
  for editors.

## Open Questions

- None left. The stash question — what to do when the stash a page named has been
  popped from another window — is settled by the reopen: the commit is looked for
  among the stashes there are now, and the page stays closed when it is gone.
  A page about a stash that does not exist has nothing to show, and saying so in
  a page nobody asked to reopen would be noise on a return.
