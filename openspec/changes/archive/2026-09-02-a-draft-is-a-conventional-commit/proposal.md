## Why

The drafting feature asks Claude for a commit message and hands the answer to
the commit page's two fields. What it asks for today is *this* repository's
voice: the prompt carries the last twenty subjects and the code beside it says,
in as many words, that this repository does not write `fix: update handler`.

That is one house's style stated as the feature's default. Most repositories
that draft a message want the format their tooling reads — changelogs, release
tooling and version bumps all key off Conventional Commits — and a draft in
narrative prose has to be rewritten by hand into `feat(scope): …` before it can
be committed. The default is the wrong way round: prescribe the format that is
a standard, and let a repository with a voice of its own turn it off.

Requested directly, 2026-09-01, naming
[Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
and the types `build`, `chore`, `ci`, `docs`, `style`, `refactor`, `perf` and
`test` beside `feat` and `fix`.

## What Changes

- A drafted message is a Conventional Commit **by default**: the summary is
  `<type>[optional scope][!]: <description>`, the type one of `feat`, `fix`,
  `build`, `chore`, `ci`, `docs`, `style`, `refactor`, `perf` or `test`, the
  scope a noun in parentheses naming a part of the codebase, and a breaking
  change marked either with `!` before the colon or a `BREAKING CHANGE:`
  footer in the description.
- A setting turns it off — **Draft conventional commit messages**, on the Git
  settings page, on by default — and with it off the draft is asked for in the
  repository's own voice exactly as it is today.
- The recent subjects still go with the request either way, but with the
  format prescribed they inform the words and the scope names rather than the
  shape of the subject line: a repository of narrative subjects would
  otherwise drag the answer back out of the format it was asked for.

## Capabilities

### Modified Capabilities

- `commit-message-drafts`: an added requirement — what shape a draft has, and
  the setting that chooses it; and a modified requirement — the subjects are
  still sent, with what they are for stated now that they are no longer the
  only thing shaping the summary.

### New Capabilities

<!-- none: this is the drafting feature's own default, restated. -->

## Impact

- **AbydosKit**: `ClaudeDraft.prompt` gains the format it asks for and
  `ask`/`draft` the flag that chooses it; a small `ConventionalCommit` reader
  so what the tests assert is the format itself rather than a sentence about
  it. `Settings` gains one Bool, registered on by default.
- **AbydosApp**: one toggle row on the Git settings page; `ChangesPane` passes
  the setting when it asks. Nothing about the two fields, the button or the
  first-use notice changes.
- **Driver**: a step that prints the prompt that *would* be sent, so the
  format asked for can be read off a driven run without a `claude` on the
  machine.
