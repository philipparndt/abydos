## Context

`ClaudeDraft` (AbydosKit) builds one prompt from the staged diff, the last
twenty subjects and the names of files too large to send, runs `claude -p` with
it on stdin, and splits the answer into summary and description at the first
line. `ChangesPane` presses it and fills the two fields. The
`commit-message-drafts` spec records the subjects-seeding requirement with a
rationale that rejects `fix: update handler` by name — so this change modifies
a requirement rather than only adding one.

## Goals / Non-Goals

**Goals:**

- A drafted summary in Conventional Commits v1.0.0 form by default, with the
  ten types the request names.
- One setting, on by default, that returns the old behaviour whole.
- Tests that assert the *format*, not the wording of the instruction.

**Non-Goals:**

- No rewriting of what comes back into the format (see below).
- No validation of hand-typed messages: this is about what the draft asks for,
  not a lint on the commit field. A person typing their own summary is not
  corrected.
- No changelog generation, no version bumping, no release tooling. The format
  is what those tools read; producing them is not this change.
- No per-repository configuration file (`.commitlintrc`, `cz.json`) is read.
  A repository that has one has it for its tooling; reading it is a change of
  its own and needs a decision about precedence.

## Decisions

### The format is prescribed in the prompt, and what comes back is not rewritten

The prompt names the shape, the ten types, the scope form and both ways of
marking a breaking change, and the answer is parsed exactly as it is today.

Ruled out: repairing a non-conforming answer by prepending a type. To prepend
`chore:` to a summary is to *classify* somebody's change, and a wrong
classification is worse than an unprefixed line — it reads as deliberate and
lands in a changelog under the wrong heading. Also ruled out: asking again
when the answer does not conform. Two `claude` runs for one press doubles the
wait on the failure the prompt already makes unlikely, and both fields stay
editable, which is the recovery.

### The subjects still go, demoted to vocabulary

Twenty narrative subjects and an instruction to write `feat(scope): …` are
contradictory instructions, and the examples usually win. So with the format
on, the prompt says the subjects are there for the words and the scope names —
what this codebase calls its parts — and that the subject line's shape is the
format's, not theirs.

Ruled out: dropping the subjects when the format is on. The scope is the half
of the format a model cannot guess well from a diff alone: `fix(navigator):`
against `fix(ProjectNavigatorViewController):` is the difference between a
scope and a file name, and the recent subjects are where a repository's own
nouns are written down.

### One setting, on the Git page, on by default

`Settings.conventionalCommitDrafts`, registered `true`, read by `ChangesPane`
when it asks — the shape `concealsSecrets` has. On the Git page rather than the
editor's: it is about commits, and the page already holds how pulling behaves.

With it off the prompt is *byte for byte* what it is today, which is what a
test asserts: a setting that "mostly" restores the old behaviour would leave
this repository's own drafts subtly worse and nobody would know which change
did it.

### `ConventionalCommit` reads a summary; nothing writes one

A small reader in the kit — type, scope, breaking, description — so the tests
can say "this is a conventional summary" about real strings, and so a future
change that wants to show the type on screen has the seam. It is read-only on
purpose: see the first decision.

## Risks / Trade-offs

- [The model answers outside the format anyway] → the fields are editable and
  the summary is one line to fix; the alternative was fabricating a type.
- [This repository's own drafts change shape unless somebody turns the setting
  off] → true, and it is the point of a default: the house rules say what this
  repository's commits look like, and this repository is one user of the
  feature rather than its specification.
- [`BREAKING CHANGE:` in the description looks like prose] → it is a footer and
  belongs in the body field; the parse already puts everything after the first
  line there, so nothing new is needed and nothing is reformatted.

## Open Questions

- Whether a repository's own commitlint configuration should override the
  setting is left until somebody has one and minds; the precedence question
  (file over setting, or setting over file) is the part that needs deciding.
