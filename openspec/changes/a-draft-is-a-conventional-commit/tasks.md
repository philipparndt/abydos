## 1. What is asked for (AbydosKit)

- [x] 1.1 `Settings.conventionalCommitDrafts`, registered `true`, the shape `concealsSecrets` has
- [x] 1.2 `ClaudeDraft.prompt` takes the flag and, when it is on, prescribes the v1.0.0 form, the ten types, the scope's noun-in-parentheses and both ways of marking a breaking change; `ask` and `draft` carry the flag through
- [x] 1.3 With the flag off, the prompt is byte for byte what it is today
- [x] 1.4 `ConventionalCommit` reads a summary into type, scope, breaking and description — read-only, so the tests can assert the format about real strings

## 2. Choosing it (AbydosApp)

- [x] 2.1 A **Draft conventional commit messages** toggle on the Git settings page, with the help text saying what the format is for
- [x] 2.2 `ChangesPane` passes the setting when it asks; nothing else about the button, the fields or the first-use notice changes

## 3. Proving it

- [x] 3.1 Kit tests: the default prompt names the form and every one of the ten types; the flag off leaves the old prompt unchanged; the subjects go either way; `ConventionalCommit` reads a scope, a `!` and a plain summary, and refuses a summary with no type
- [x] 3.2 A driven run: a step that prints the prompt that would be sent, showing the format asked for with the setting on and its absence with the setting off — no `claude` on the machine needed
- [x] 3.3 The settings page shows the toggle on by default, read off a driven run

## 4. Before finishing

- [x] 4.1 `make test` clean, `make warnings` clean, machine load said if a bound flakes
- [x] 4.2 `openspec/specs/commit-message-drafts/spec.md` is not made untrue: the subjects requirement is modified rather than left standing beside a contradicting one
