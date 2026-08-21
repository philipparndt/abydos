## 1. Finding what a session left

- [x] 1.1 The slug: a project's absolute path with every `/` and `.` turned into
      `-`. Pure, in `AbydosKit`, with the cases that bite — a path under a
      symlinked `/tmp`, a worktree under `.claude` (which produces a double
      dash), a trailing slash, and a path with a dot in a directory name.
- [x] 1.2 The sessions for a project: the directories under
      `/tmp/claude-<uid>/<slug>/`, each with what it holds — scratchpad,
      `tasks/`, when it last wrote, how much is in it.
- [x] 1.3 The transcript beside one: `~/.claude/projects/<slug>/<id>.jsonl`, and
      the first user message read from **the head of the file**. Bounded by
      bytes, not by lines: one record of a twenty-megabyte transcript.
- [x] 1.4 Ordered newest first, and a session with nothing left is not in the
      list at all. Of the fifteen directories this repository has on this
      machine, seven have files in them; the other eight are listed nowhere.
- [x] 1.5 Tests over all of it, against a directory tree made by the test —
      including a transcript that is missing, one that is not JSON, and one whose
      first record is not a user message. Plus a live suite that reads the real
      ones on this machine, because **another program's layout is not a contract
      and a suite that only reads its own fixtures cannot notice it changing**.

      It earned itself immediately: the real transcripts showed a session whose
      first message is `/clear`, and a row labelled "/clear" says nothing about
      what that session was for. A bare slash command is now a last resort — the
      request after it wins, a command *with* arguments is taken as typed, and
      `/clear` is still used when there is nothing else, because it beats an id.
      The same run showed a scratchpad holding 3,409 files and 27 MB, which is
      what the walk's bound is for., against a directory tree made by the test —
      including a transcript that is missing, one that is not JSON, and one whose
      first record is not a user message.

## 2. The root

- [x] 2.1 A third root, absent when it holds nothing, in the order the modified
      requirement names: the project, `Dependencies`, `Claude Sessions`.
- [x] 2.2 A session row, labelled by what was asked, when it last wrote and how
      much it holds, with the transcript's path on its tooltip.
- [x] 2.3 Its children are ordinary file rows — `FileNode`, the same as a
      package's, and no second kind. **Which directory a row opens onto answers
      the design's third open question**: a session that only wrote a scratchpad
      opens straight onto its files, since an intermediate `scratchpad` row
      would be a click for nothing; one that also ran subagents opens onto the
      session's own directory, so `scratchpad` and `tasks` are both there, named
      as they are on disk. Neither invents a row. — `FileNode`, the same as a
      package's, and no second kind.
- [x] 2.4 An icon for the root — a clock, because everything under it is sorted
      by when — and one for a session row, which is neither the dependency
      shelf's box nor a folder. and for a session row that are not the
      dependency shelf's.

## 3. Reveal

- [x] 3.1 A file from a scratch directory is revealed under its session's row.
      Driven: `claimed-by=sessions selection=repro.log@32`, and from a `tasks/`
      directory too.
- [x] 3.2 The claim order holds and is checked: the reveal report says which of
      the three claimed a file, so "the tree answered" and "the session root
      answered" can be told apart from outside.: nothing lives in two roots, and
      a file under `/tmp/claude-*` is claimed by this one.
- [x] 3.3 A file from a session of *another* project is not claimed here:
      `claimed-by=tree`, unplaceable. **The sentence it says had to change** —
      it listed the roots that could have held the file and there is a third one
      now, so it says "no package or toolchain in Dependencies holds it, and no
      session left it behind".

## 4. When to read it

- [x] 4.1 Read on the refresh the rest of the tree takes, and compared before
      redrawing: `reloadData` throws away every row's identity, so a root that
      rebuilt on each refresh would collapse what somebody had open while they
      were reading it. **No watcher on `/tmp`:** **No watcher on
      `/tmp`**: it is written by every agent on the machine, and a section
      nobody is looking at must not cost anything.
- [x] 4.2 The project the window is on, read where the rest of the tree is read,
      so it follows a window that changes project — the rule the panel's panes
      already keep., following it when the window changes
      project — the rule the panel's panes already keep.
- [x] 4.3 **Measured, and the first answer was not good enough.** Reading the
      seven sessions this repository has took **127 ms**, because it walked
      6,920 files — one scratchpad holds 3,409 of them and 27 MB, a scratchpad
      being somebody's working directory and sometimes a whole checkout. A tenth
      of a second on the project-open path, growing with every session anybody
      ever ran, for two numbers in a subtitle.

      Split in two: the cheap read is three stats and a shallow listing per
      session — **10 ms** — and the walk happens afterwards on a background
      queue, **224 ms**, landing on the rows when it is done. Load 14.0 over 10
      cores. Until it lands a row says when, and not how much, because "0 files"
      before the walk is a lie for as long as it is up.

## 5. Watched

- [x] 5.1 Against a scratchpad copy, never a real checkout. Three sessions
      fabricated for the copy's own path — the real repository's would have meant
      driving the app at a real checkout — with backdated files, one carrying a
      `tasks/` directory and one with no transcript:

          Claude Sessions — 3 sessions
            /opsx:apply a-value-beside-the-code-can-be-opened-up [today 11:26 · 2 files · 14 B]
            33333333                                            [yesterday 14:00 · 1 file · 27 B]
            the backlog does not show the progress bar…         [18 Aug · 2 files · 23 B]

      The reading of *real* sessions is held by the live suite instead, which is
      read-only and needs no window.
- [x] 5.2 A file inside one is revealed back under its session, from a
      scratchpad and from a `tasks/` directory — the second showing `scratchpad`
      and `tasks` side by side under the row, which is the shape a session that
      ran subagents gets.
- [x] 5.3 A project with no sessions has no third root: `project=linkrepo
      dependencies=absent sessions=absent` — and that project has no second one
      either, so it is one root, as it was before this change.
- [x] 5.4 A session whose transcript is missing still has a usable row: the id's
      first characters, drawn in the grey a note uses rather than as a title
      somebody wrote, with its date and size beside it.

## 6. Finish

- [x] 6.1 `project-view` says the tree has up to three roots, each there only
      when it holds something, in what order they claim a revealed file, what
      the new one holds, how a row under it is labelled and how it behaves.

      **The sentences this made untrue**, both found and both fixed:

      - *"The tree has two roots"*, which the delta rewrites — known in advance
        and the reason this modifies `project-view` rather than adding a
        capability.
      - *"it is outside the project, and no package or toolchain in Dependencies
        holds it"* — what the tree says about a file it cannot place. It lists
        the roots that could have held it, and there is a third one now.

      Two comments in the code said "a second root" where they meant the
      Dependencies one; and **"collapse all" collapsed two roots and would have
      left the third open** — found by grepping for what claimed the count
      rather than by watching it.
- [x] 6.2 `make test` and `make warnings`, both clean, exit codes trusted.
      `make test exit=0` — 3121 tests in 411 suites, 2 known issues, load 11.5
      over 10 cores. `make warnings exit=0`, four warnings, all four in vendored
      tree-sitter C.
- [x] 6.3 What was ruled out on the way:

      - **A shelf inside `Dependencies`.** Asked for explicitly, and right: the
        heading says what a project depends on, and a directory of reproductions
        from last Tuesday is not that.
      - **Counting a session's files on the project-open path.** Measured, not
        assumed: 127 ms for seven sessions and 6,920 files, growing with every
        session anybody ever ran. The read is 10 ms now and the walk happens
        behind it.
      - **Saying "0 files" before the walk lands.** A subtitle that is wrong for
        a tenth of a second on the row somebody is looking at. It says when, and
        gains how much.
      - **A watcher on `/tmp/claude-<uid>`.** Every agent on the machine writes
        there, several times a second while one is working, for a root nobody
        may be looking at.
      - **Inverting the slug.** `/` and `.` both map to `-`, so two paths can
        produce one name. A project's own path produces one directory; that one
        is read and nothing is guessed. `/tmp` being a symlink is the one place
        two spellings are tried, because a session filed under the resolved form
        genuinely exists on this machine.
      - **A global list of every session.** The window has one project and the
        tree is about it.
      - **The memory directory.** `~/.claude/projects/<slug>/memory/` is small
        and interesting and is a different thing with a different lifetime.
        Worth its own item.
      - **Deleting a session's files from a row.** Those directories are the
        only copy of what a run produced.

      **The three open questions, answered by the work:**

      - *Whether `tasks/` deserves its own row* — a session that only wrote a
        scratchpad opens straight onto its files; one that also ran subagents
        opens onto its own directory so `scratchpad` and `tasks` are both there,
        named as they are on disk. Neither invents a row.
      - *How much of the first message to show* — 120 characters, one line,
        whitespace collapsed. Long enough for the sentences real transcripts
        begin with, and the whole of it is on the tooltip.
      - *Whether a session whose files went with a reboot should say so* — it
        has no row, and that is now also what happens to one the walk finds
        empty. A row leading nowhere is worse than an absence, and the
        transcript it would speak for is not something this shows.

      Two notes on the watching itself: the tree pane did not appear in the
      screenshots of any driven run — a fresh throwaway defaults domain opens
      with the sidebar collapsed to its rail — so the evidence here is the
      textual reports, which this project prefers anyway. And the sessions
      driven against were fabricated for the scratchpad copy's own path, because
      the real ones belong to a real checkout.
