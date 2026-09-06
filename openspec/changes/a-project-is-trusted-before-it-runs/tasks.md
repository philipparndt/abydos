## 1. The store, and the question

- [ ] 1.1 `Sources/AbydosKit/Project/ProjectTrust.swift` — the list in
  `~/Library/Application Support/Abydos/trust.json`, the shape and the
  init-time load `RecentProjects` has, and its rule that **a driven run keeps
  the list in memory and never writes it**. Entries: the resolved path, the
  date, and whether the gesture was this folder or everything under it.
- [ ] 1.2 `isTrusted(_ root:)` — resolved-path match, and the parent rule at a
  component boundary so `~/dev` covers `~/dev/abydos` and not `~/development`.
  A decision type rather than a `Bool` where a call site can say something
  useful about why.
- [ ] 1.3 `ProjectTrustTests` — trusting a folder, a parent covering a child,
  the `~/development` near-miss, a symlinked and a `/tmp` path resolving to the
  same answer (which is where `/private` bit `GitRepository` before), a
  withdrawal, and a driven run leaving the file untouched.

## 2. The gates

- [ ] 2.1 Run, debug, build, test, Make goals and the gradle and maven
  wrappers: the gate at the point of execution rather than at the point of
  display, and one sentence for the refusal with the gesture that changes it.
- [ ] 2.2 Devcontainers, and any image the project names.
- [ ] 2.3 Language servers, formatters and linters — including the ones found
  in the project's own tree, which is the case a machine-wide binary check
  would miss.
- [ ] 2.4 The terminal: no shell in an untrusted project's directory, and the
  panel says why rather than looking broken. A shell there sources whatever the
  machine's configuration sources, and direnv exists to run the project's own
  `.envrc`.
- [ ] 2.5 Schemes, tasks and agent commands the project carries.

## 3. The environment

- [ ] 3.1 One place that assembles a project's environment, so there is one
  place to drop it: while untrusted, no `launch.json` `env`, no
  `containerEnv`, no `.envrc`, no run configuration's own. Dropped, not
  filtered — `SOPS_AGE_KEY_CMD` reads like configuration and is a command.
- [ ] 3.2 The application's own environment is untouched: the `PATH` it needs,
  and the variables it sets for git's and sops's prompts, are this app's.
- [ ] 3.3 A test per hole named in the report: `SOPS_AGE_KEY_CMD` absent from
  what `Sops` is run with, `GIT_SSH_COMMAND` and `GIT_EXTERNAL_DIFF` absent
  from what `GitRepository.run` is given, and a `launch.json` `env` reaching
  nothing at all because nothing is launched.

## 4. Git hooks

- [ ] 4.1 A commit in an untrusted project declines the hooks, and says so
  where the commit is made rather than in a settings page — with the wording
  checked in a test, since "what is said" is the requirement.

## 5. The window and the settings

- [ ] 5.1 The strip: what is held back, in a sentence, and **Trust This
  Project**. A strip and not a modal — a window that cannot be looked at until
  a security question is answered is a question answered by reflex.
- [ ] 5.2 The sheet: the folder named, the parent folder offered as the wider
  choice, and what trusting turns on said before it is granted.
- [ ] 5.3 The settings page: what is trusted, and taking it back.

## 6. Proving it

- [ ] 6.1 The engine's half in tests, as above — the store, the parent rule and
  the environment.
- [ ] 6.2 A driven run over a scratch project that is deliberately hostile to
  itself: a `Makefile` whose default goal writes a file, a `launch.json` with
  an `env`, a devcontainer definition, a `pre-commit` hook that writes a file,
  and a `.envrc`. Untrusted, every gesture refused and **no file written by any
  of them**; trusted, the same gestures doing what they always did. The file
  each of them would have written is the proof, since "nothing ran" is
  otherwise a claim about an absence.
- [ ] 6.3 The strip and the sheet photographed, and the settings page listing
  and withdrawing.

## 7. Finishing

- [ ] 7.1 `Scripts/file-size-allowed.txt` for what grew, reasons said aloud;
  `docs/release-notes-0.14.0.md` given the section, including what this is not
  — not a sandbox, and not a scanner.
- [ ] 7.2 `make test` and `make warnings`, both clean by their exit codes.
