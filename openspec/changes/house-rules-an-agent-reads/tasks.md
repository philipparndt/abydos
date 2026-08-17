## 1. Decide where they live

- [ ] 1.1 Choose between `project.md`, a root `CLAUDE.md`, the prompt, and a file of
      the project's own that `project.md` points at. Write down what killed each of
      the others — the prompt is refused by its own comment, and `project.md` belongs
      to the published `backlog-spec` tool rather than to Abydos.
- [ ] 1.2 Decide whether `CLAUDE.md` holds the rules or points at them, and make sure
      the answer leaves exactly one copy.
- [ ] 1.3 Decide where today's facts go, and whether that file is committed. It
      cannot be both freely editable and version-visible.

## 2. Write them

- [ ] 2.1 Write the permanent rules, once, from the list in the proposal, each with
      the failure that motivated it.
- [ ] 2.2 Write today's separately, with a line at the top saying it describes a
      particular day and which.
- [ ] 2.3 Mark which rules a program already keeps — `NamedSuiteTests` for
      `TestDefaults.make()`, and 0534's guard for app launches once it lands.

## 3. Check it behaviourally, not editorially

- [ ] 3.1 Start a throwaway item with the tool and nothing added to the prompt by
      hand, and see whether the agent knows a rule it was not given.
- [ ] 3.2 Check the same for an agent working in the repository that the tool did not
      start, since that is most of them.
- [ ] 3.3 Confirm `BacklogRunner.prompt` still contains no copy of the rules.

## 4. Finish

- [ ] 4.1 Write down what was ruled out on the way, including the four candidate
      locations and why three lost.
- [ ] 4.2 `.abydos/backlog/spec/backlog.md` says what the project now does.
- [ ] 4.3 Note that `start` printing the `cd` and the prompt when no agent launches
      stops being a workaround for missing rules and becomes a deliberate path.
