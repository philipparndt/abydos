## Context

What is on disk, measured on this machine today:

    /tmp/claude-<uid>/<slug>/<session-id>/scratchpad     15 sessions for this project
    /tmp/claude-<uid>/<slug>/<session-id>/tasks          subagent output, when there was any
    ~/.claude/projects/<slug>/<session-id>.jsonl         the transcript, 20 MB for this one
    ~/.claude/projects/<slug>/memory/                    what an agent chose to remember

`<slug>` is the project's absolute path with every `/` and `.` replaced by `-`:
`/Users/philipparndt/dev/abydos` becomes `-Users-philipparndt-dev-abydos`, and a
worktree under `.claude` becomes `-Users-philipparndt-dev-abydos--claude-worktrees-…`.
The same key is used in both places, which is what makes a scratch directory and
a conversation pairable: **the directory's name under `/tmp` is the session id,
and the transcript is that id under `~/.claude/projects/<slug>/`.**

`/tmp` is a symlink to `/private/tmp` here, so the same path is spelled two ways
depending on who resolved it. And `/tmp` is cleared on reboot, so a scratch
directory is a thing with a lifetime, unlike the transcript beside it.

What exists to build on: *Dependencies* is a second root holding rows that are
directories, read from disk, listing lazily, and allowed to win over the ordinary
tree when a file inside one is revealed. `DependencyTree.Row` is the model for
it, `FileNode` is what a directory row's children are, and the reveal goes
through `DependencyTree.locate`.

## Goals / Non-Goals

**Goals:**

- The files a past session left for *this* project are one click from the tree.
- A row says which session it was, in a way somebody recognises.
- Nothing is written into another program's directories, and nothing is run.
- A project no agent has touched looks exactly as it does today.

**Non-Goals:**

- Reading a transcript as a document, or rendering a conversation.
- Managing the sessions: no deleting, no archiving, no reclaiming `/tmp`.
- Sessions for other projects, or a global list of every session on the machine.
- Any agent other than Claude Code. The paths are its own, and inventing a
  general shape for a single known layout is a guess with no second example.

## Decisions

**A root of its own, and here is the argument it has to beat.**
`DependencyTree` records, where the toolchain rows were added, three reasons
*against* a third root: the reveal is allowed one place that wins over the
ordinary tree and a second would need its own copy of that rule; the section's
heading already covers "what the project is made from"; and **a root of its own
would have to exist before anything had been found to put in it, which is a
permanent empty row on every project.**

The third is the real one, and it does not apply here. Whether a session has
left anything is *knowable before anybody asks* — the directory either exists or
it does not — where a toolchain's row cannot be known until a symbol is followed
out of the project. So this root can follow the rule *Dependencies* follows: it
is there when it has something in it, and absent when it has not.

The first is answered by scope: the reveal rule stays one rule with two claimants
in a fixed order — the ordinary tree, *Dependencies*, then this — and a file
under `/tmp/claude-*` is in none of the others, so the order never has to be
argued about. The second is answered by the heading itself: what a session left
behind is not what the project is made from, and filing it under a heading that
says so would be the same stretch the toolchain rows were accused of.

**The name is "Claude Sessions", and the two shorter names are both taken.**
"Scratch" collides with the app's own Scratches pane, which is a different
feature about files somebody writes on purpose. "Sessions" collides with the
`sessions` capability, which is the editor's tabs and splits coming back. Naming
the vendor is honest rather than awkward: the paths are Claude Code's, and a
section pretending to be about agents in general would be a promise with one
implementation behind it.

**A row is labelled by time, size and the first thing that was asked.** A UUID
identifies nothing to a person. The recognisable part of a session is what it was
*for*, and that is the first user message in the transcript — read from the head
of the file, one record, never the whole thing: this session's transcript is
twenty megabytes and there are eighteen of them for this project alone.

**The transcript is not a row.** It is where the label comes from, and its path
is on the row's tooltip for anybody who wants to point another tool at it. A
twenty-megabyte JSONL opened in the editor is not reading a conversation, and
offering it as a file would invite exactly that.

**Read when the tree reads, not watched.** `/tmp` gets a directory per session
and is written by programs this app does not own; a watcher on it would fire
during every agent's every write, for a section nobody is looking at. The section
is read on the same refresh the rest of the tree takes, which is what
*Dependencies* does.

**The project the window is on, not the repository.** A worktree has a slug of
its own, and its sessions are its own. This follows the window, the way the
search pane and the panel's panes do.

**Ruled out: putting it under `Dependencies`.** Asked for explicitly, and it is
also right: the heading says what a project depends on, and a directory of
reproductions from last Tuesday is not that.

**Ruled out: a global "all sessions" list.** The window has one project and the
tree is about it. A machine-wide list is a different tool, and the one-liner in
the proposal already writes it for anybody who wants one.

**Ruled out: opening the memory directory as part of this.**
`~/.claude/projects/<slug>/memory/` is small, readable, and genuinely
interesting — and it is a different thing from a scratch directory, filed under a
different root, with a different lifetime. Worth its own item rather than a
second kind of row here.

**Ruled out: deleting a session's files from the row.** Reclaiming `/tmp` is a
gesture with a real risk — those directories are the only copy of what a run
produced — and this item is for finding things. A future one can take it, with a
confirmation that says what goes.

**Ruled out: canonicalising the slug ourselves and hoping.** The mapping is
lossy: `/` and `.` both become `-`, so two paths can produce one key. Rather than
inventing a reverse mapping, the section reads the directory that the project's
own path produces, and nothing else.

## Risks / Trade-offs

- **`/tmp` is cleared on reboot**, so a row can disappear between one day and the
  next while its transcript stays. → The section shows what is on disk; a session
  with nothing left has no row, rather than a row leading nowhere.
- **Another program's layout is not a contract.** If Claude Code moves these
  directories the section empties. → It empties quietly, which is the same thing
  as a project nobody has worked on, and it is a section rather than a promise.
- **A slug collision** would show one project another's sessions. → Possible and
  unlikely; the row's tooltip carries the full path, which is where somebody
  would notice.
- **Somebody's private working notes in the tree.** These are files on their own
  machine, already readable by everything else on it, and shown only for the
  project they belong to.

## Open Questions

- **Whether the root should also appear when the scratch is gone but the
  transcript is not** — a row that can say "this session's files went with the
  last reboot" is arguably better than silence, and arguably a row that leads
  nowhere.
- **How much of the first message to show.** A line is not much of a title for a
  session that ran all day, and the whole of it is a paragraph in a tree row.
- **Whether `tasks/` deserves its own row** under a session, or should sit
  beside the scratchpad's files as one flat list.
