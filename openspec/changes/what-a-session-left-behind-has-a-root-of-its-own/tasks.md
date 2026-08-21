## 1. Finding what a session left

- [ ] 1.1 The slug: a project's absolute path with every `/` and `.` turned into
      `-`. Pure, in `AbydosKit`, with the cases that bite — a path under a
      symlinked `/tmp`, a worktree under `.claude` (which produces a double
      dash), a trailing slash, and a path with a dot in a directory name.
- [ ] 1.2 The sessions for a project: the directories under
      `/tmp/claude-<uid>/<slug>/`, each with what it holds — scratchpad,
      `tasks/`, when it last wrote, how much is in it.
- [ ] 1.3 The transcript beside one: `~/.claude/projects/<slug>/<id>.jsonl`, and
      the first user message read from **the head of the file**. Bounded by
      bytes, not by lines: one record of a twenty-megabyte transcript.
- [ ] 1.4 Ordered newest first, and a session with nothing left is not in the
      list at all.
- [ ] 1.5 Tests over all of it, against a directory tree made by the test —
      including a transcript that is missing, one that is not JSON, and one whose
      first record is not a user message.

## 2. The root

- [ ] 2.1 A third root, absent when it holds nothing, in the order the modified
      requirement names: the project, `Dependencies`, `Claude Sessions`.
- [ ] 2.2 A session row, labelled by what was asked, when it last wrote and how
      much it holds, with the transcript's path on its tooltip.
- [ ] 2.3 Its children are ordinary file rows — `FileNode`, the same as a
      package's, and no second kind.
- [ ] 2.4 An icon for the root and for a session row that are not the
      dependency shelf's.

## 3. Reveal

- [ ] 3.1 A file from a scratch directory is revealed under its session's row.
- [ ] 3.2 The claim order holds and is checked: nothing lives in two roots, and
      a file under `/tmp/claude-*` is claimed by this one.
- [ ] 3.3 A file from a session of *another* project is not claimed here, and
      says what it says today.

## 4. When to read it

- [ ] 4.1 Read on the refresh the rest of the tree takes. **No watcher on
      `/tmp`**: it is written by every agent on the machine, and a section
      nobody is looking at must not cost anything.
- [ ] 4.2 The project the window is on, following it when the window changes
      project — the rule the panel's panes already keep.
- [ ] 4.3 Reading it costs nothing measurable on a project with fifteen sessions
      in it. Measured with the load beside the number.

## 5. Watched

- [ ] 5.1 Against a scratchpad copy, never a real checkout: this repository has
      fifteen sessions on this machine — the root appears, the rows are in time
      order, and one opens.
- [ ] 5.2 A file inside one opens in a tab, and is revealed back under its
      session.
- [ ] 5.3 A project with no sessions has two roots and no empty third.
- [ ] 5.4 A session whose transcript is missing still has a usable row.

## 6. Finish

- [ ] 6.1 `project-view` says the tree has three roots, what the new one holds,
      and how a row under it behaves. Name any sentence this makes untrue — the
      "two roots" sentence is the one already known.
- [ ] 6.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 6.3 Write down what was ruled out on the way, including the three
      questions the design leaves open.
