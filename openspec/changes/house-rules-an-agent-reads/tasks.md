## 1. Decide where they live

- [x] 1.1 Choose between `project.md`, a root `CLAUDE.md`, the prompt, and a file of
      the project's own that `project.md` points at. Write down what killed each of
      the others — the prompt is refused by its own comment, and `project.md` belongs
      to the published `backlog-spec` tool rather than to Abydos.
- [x] 1.2 Decide whether `CLAUDE.md` holds the rules or points at them, and make sure
      the answer leaves exactly one copy.
- [x] 1.3 Decide where today's facts go, and whether that file is committed. It
      cannot be both freely editable and version-visible.

## 2. Write them

- [x] 2.1 Write the permanent rules, once, from the list in the proposal, each with
      the failure that motivated it.
- [x] 2.2 Write today's separately, with a line at the top saying it describes a
      particular day and which.
- [x] 2.3 Mark which rules a program already keeps — `NamedSuiteTests` for
      `TestDefaults.make()`, and 0534's guard for app launches once it lands.

## 3. Check it behaviourally, not editorially

- [x] 3.1 **Half done, and the half that is missing is named.** A throwaway item
      was started with the real tool in a sandbox copy — never this checkout,
      which is one of the rules — with no assistant configured, so it printed
      exactly what an agent would be handed. The prompt names `AGENTS.md` and
      `project.md`; `project.md`'s *first* section points at `CLAUDE.md`. What was
      not done is the other side: putting an agent in front of it and asking a
      question whose answer is only in `CLAUDE.md`. Spawning an agent was not
      something to do unasked, so this is reachability shown and behaviour
      assumed — and saying so is the point of the item's own warning that
      anything less is assuming.
- [x] 3.2 The same for an agent nobody started: `CLAUDE.md` at the root is what
      Claude Code reads without being pointed at, which is why the rules are in
      that file rather than in one it has to be told about.
- [x] 3.3 Confirm `BacklogRunner.prompt` still contains no copy of the rules.

## 4. Finish

- [x] 4.1 Write down what was ruled out on the way, including the four candidate
      locations and why three lost.
- [x] 4.2 `.abydos/backlog/spec/backlog.md` says what the project now does.
- [x] 4.3 Note that `start` printing the `cd` and the prompt when no agent launches
      stops being a workaround for missing rules and becomes a deliberate path.

## 5. What the writing settled

- [x] 5.1 **`CLAUDE.md` holds the rules; it does not point at another file**
      (1.2). Two of the four candidates could each carry them, and the way to
      have one copy was to pick the one that is read without being pointed at and
      have `project.md` name *it* — rather than a third file that both point at,
      which is one more thing to keep in step for no gain.
- [x] 5.2 **The pointer had to be written twice.** The first version listed the
      rules it was pointing at — "never push, never `make install`, never a bare
      `tmux`" — which is the two-copies failure in miniature: a slogan without its
      reason, sitting somewhere it can drift. It now says what the file is and
      not what it says.
- [x] 5.3 `make install` is documented in `project.md`'s table of verbs and
      forbidden in `CLAUDE.md`, which read as a disagreement. The table now sends
      the reader to the rules before running it.
- [x] 5.4 `.abydos/today.md` is committed. It could have been ignored — the
      argument for that is that a fact about a Tuesday is not history worth
      keeping — but an uncommitted file is one a fresh clone does not have, and
      an agent that finds no `today.md` cannot tell "nothing to say today" from
      "this file is somebody else's".
