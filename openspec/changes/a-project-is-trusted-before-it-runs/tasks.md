## 1. The store, and the question

- [x] 1.1 `Sources/AbydosKit/Project/ProjectTrust.swift` — the list in
  `~/Library/Application Support/Abydos/trust.json`, the shape and the
  init-time load `RecentProjects` has, and its rule that **a driven run keeps
  the list in memory and never writes it**. Entries: the resolved path, the
  date, and whether the gesture was this folder or everything under it.
- [x] 1.2 `isTrusted(_ root:)` — resolved-path match, and the parent rule at a
  component boundary so `~/dev` covers `~/dev/abydos` and not `~/development`.
  A decision type rather than a `Bool` where a call site can say something
  useful about why.
- [x] 1.3 `ProjectTrustTests` — trusting a folder, a parent covering a child,
  the `~/development` near-miss, a symlinked and a `/tmp` path resolving to the
  same answer (which is where `/private` bit `GitRepository` before), a
  withdrawal, and a driven run leaving the file untouched.

## 2. The gates

- [x] 2.1 Run, debug, build, test, Make goals and the gradle and maven
  wrappers: the gate at the point of execution rather than at the point of
  display, and one sentence for the refusal with the gesture that changes it.
- [x] 2.2 Devcontainers, and any image the project names.
- [x] 2.3 Language servers, formatters and linters — including the ones found
  in the project's own tree, which is the case a machine-wide binary check
  would miss.
- [x] 2.4 The terminal — **and this one was reversed**, which is the useful
  part of the task. The first cut refused a shell in an untrusted project's
  directory. Reported: "why is the terminal hidden, does this increase the
  security? This would make it hard to switch between projects." It barely
  does: the shell and its configuration are the person's own, typing `make` in
  it is them choosing to run the project's code exactly as they would in
  Terminal.app, and direnv already refuses an `.envrc` it has not been
  allowed — while refusing costs the way somebody moves between projects in a
  terminal-first editor. So the terminal opens, `DIRENV_DISABLE` is set for an
  untrusted project (belt to direnv's brace, best-effort by nature), and the
  rule left standing is the sharper one: this app starts nothing of the
  project's by itself, and does not police what anybody types.
- [x] 2.5 The agent commands: `startBacklogItem` refuses in an untrusted
  project, because an agent started in one reads that project's instructions
  and acts on them — a `CLAUDE.md` in a downloaded repository is a list of
  things somebody else wants run on this machine. **Two things this task
  assumed and the code did not have:** the "schemes" of `SchemeLibrary` are
  colour schemes and execute nothing, and the commit-message draft is already
  behind its own per-project consent for sending a diff, which is the question
  that path is actually about — neither is gated here, and saying so is
  cheaper than leaving somebody to wonder which of them was missed.

## 3. The environment

- [x] 3.1 One place that assembles a project's environment, so there is one
  place to drop it: while untrusted, no `launch.json` `env`, no
  `containerEnv`, no `.envrc`, no run configuration's own. Dropped, not
  filtered — `SOPS_AGE_KEY_CMD` reads like configuration and is a command.
- [x] 3.2 The application's own environment is untouched: the `PATH` it needs,
  and the variables it sets for git's and sops's prompts, are this app's.
- [x] 3.3 A test per hole named in the report — `SOPS_AGE_KEY_CMD`,
  `GIT_SSH_COMMAND`, `GIT_EXTERNAL_DIFF`, `DYLD_INSERT_LIBRARIES` and
  `NODE_OPTIONS` — all reaching nothing from an untrusted project, an
  ordinary-looking `LANG` going with them (dropped, not filtered), and the
  sentence that says what was dropped. **And what the survey found**: nothing
  in this app reads a project's `.env` into a process environment today, and
  the project-supplied paths are all launch paths — so the requirement is held
  by `ProjectEnvironment` at the assembly point and by the launch gates in
  front of it, rather than by one of them alone.

## 4. Git hooks

- [x] 4.1 A commit in an untrusted project declines the hooks, and says so
  where the commit is made rather than in a settings page — with the wording
  checked in a test, since "what is said" is the requirement.

## 5. The window and the settings

- [x] 5.1 The strip: what is held back, in a sentence, and **Trust This
  Project**. A strip and not a modal — a window that cannot be looked at until
  a security question is answered is a question answered by reflex.
- [x] 5.2 The sheet: the folder named, the parent folder offered as the wider
  choice, and what trusting turns on said before it is granted.
- [x] 5.3 The settings page: what is trusted, and taking it back.

## 6. Proving it

- [x] 6.1 The engine's half in tests, as above — the store, the parent rule and
  the environment.
- [x] 6.2 Driven on 2026-09-06 over a project deliberately hostile to itself
  — a `Makefile` whose goal touches a file, a `launch.json` whose `env` sets
  `SOPS_AGE_KEY_CMD` and `DYLD_INSERT_LIBRARIES`, a `pre-commit` hook that
  touches a file, and an `.envrc`. Each of them would leave a trace, which is
  the point: "nothing ran" is otherwise a claim about an absence.
  - *Untrusted, opened with a file:* `TRUST: trusted=false banner=[proj is not
    trusted — nothing in it runs, and its environment reaches nothing.]`, and
    no trace of any of them.
  - *The terminal:* refused, with the shared sentence — "proj is not trusted,
    so nothing in it runs. Trust it in the window's banner to run, debug, open
    a terminal and start language servers."
  - *The make goal:* `--run-config all` reports *starting all*, and nothing
    ran: no `RAN-MAKE`, and the same sentence in a toast.
  - *The commit:* made, with `RAN-HOOK` absent and the toast reading
    "Committed without hooks: The project is not trusted, so its hooks did not
    run."
  - *Trusted:* `--trust` and the same `--run-config all` — banner gone,
    `trusted=true`, and `RAN-MAKE` there.
  - *The store:* no `trust.json` in the real support directory afterwards, the
    driven runs having kept their answer in memory.
- [x] 6.3 The strip photographed — *proj is not trusted — nothing in it runs,
  and its environment reaches nothing*, with **Trust This Project** and *What
  is held back* beside it. **And a bug the photograph found**: the strip was
  pinned to the window's top edge, which in a window with a transparent
  titlebar is *behind* the titlebar — the report said the strip was up and the
  window did not show it. It takes the same top inset every other pane here
  takes, updated with them.

## 8. The amendment: where a clone came from

*Asked for while this was being applied: "I think it should be possible to
trust some git remotes (like an github enterprise server) instead of a whole
base dir", and then "and by remote owner (e.g. github.com/philipparndt or
github.com/my-org)".*

- [x] 8.1 `TrustedRemote` — a host, and an owner under it when there is one.
  Both in the same store, which changed shape from a bare array of folders to
  an object with two lists; the old shape is still read, since trusting
  everything again should not be the price of an update.
- [x] 8.2 The remote is read once, when the project loads: `GitForge.remoteURL`
  and its own parser give the host and the owner, and the answer is kept for
  the life of the process — a subprocess between a keypress and a refusal is a
  refusal that arrives late. The strip is refreshed when the answer lands,
  since a trusted host makes it go away.
- [x] 8.3 The sheet offers the owner first and the host second, each saying
  what it is worth: **a repository's remote is what its own `.git/config`
  claims**, so trusting one trusts every folder that says it came from there.
  Weaker than a folder, deliberately, and said where it is granted rather than
  in a release note. The settings page lists trusted remotes beside the
  folders, with the same sentence and a Withdraw each.
- [x] 8.4 Tests: a host covering every clone from it, an owner *not* covering
  the rest of its host, one spelling for `GitHub.com/My-Org`, a project with no
  remote covered by neither, the reading of the older file, and both lists
  surviving the process.
- [x] 8.5 Driven: `--trust-owner` on a project whose `origin` is
  `git@github.company.com:my-org/thing.git` — trusted, banner gone, with no
  folder entry of its own.

## 9. The amendment: the strip itself

*Two reports while it was being applied: "I dont like that the 'What is held
back' opens a toast", and "I miss a way to hide the bar without trusting".*

- [x] 9.1 *What is held back* is a popover from the button that asked, not a
  toast: it is a list somebody reads **while deciding**, and a toast goes on a
  timer and cannot be read twice. It says what still works beside what does
  not — the reading that is unaffected is the half that makes "look first,
  decide later" an option rather than a slogan.
- [x] 9.2 The strip has a dismiss, and dismissing grants nothing: the project
  stays untrusted, every refusal stands, and it lasts only until that project
  is opened again — a dismissal that outlived the session would be a safety
  decision made by somebody trying to get a bar out of the way.
- [x] 9.2a The list is **two lists rather than two paragraphs**, reported as
  "the text is to verbose (block text) which is hard to read": seven items and
  five, each with a mark — red for what waits, green for what does not, since
  `gitModified` is blue in every scheme here and reads as "changed" rather than
  as "not now". A list is scanned; a paragraph is skipped, and this is read
  while somebody decides. Photographed, and the words are in the driven report
  as well, since a photograph cannot be grepped.
- [x] 9.2b **The gap under the strip**, reported with a picture: the content
  view spans the whole window, so every pane here clears the transparent
  titlebar by taking its inset — and with the strip up, the strip clears it and
  the panes below start under the strip, so each of them was taking the
  titlebar's height a second time. The inset now goes to the strip *or* to the
  panes, never both; the left rail keeps its own, being beside the strip and
  running the window's whole height. `refreshTrustBanner` asks for the insets
  again, since putting the strip away gives them back.
- [x] 9.3 **File ▸ Trust This Project…**, because a strip that can be put away
  must not take the only way to trust with it. The shared refusal sentence
  names it beside the banner, and the item says so when the project is already
  trusted rather than opening a sheet about nothing.

## 7. Finishing

- [x] 7.1 `Scripts/file-size-allowed.txt` raised for the six files that grew
  by a gate, a flag or a page. **`MainWindowController+Layout.swift` went over
  the limit and the ceiling did not go up**: the strip, the sheet and their
  doors moved to `MainWindowController+Trust.swift`, which is state moving out
  by subject rather than braces moving — the layout file is where the window's
  panes are put together, and trust is its own question.
  `docs/release-notes-0.14.0.md` has the section, including what this is not:
  not a sandbox, and not a scanner.
- [x] 7.2 Green by their exit codes: `make test` 4130 tests in 525 suites,
  exit 0 with the suite's two standing known issues, load 118.1 over 10 cores;
  `make warnings` exit 0. Run again after the amendments, with the ledger
  raised for `AppDelegate.swift` 3815 → 3831 and `LaunchOptions.swift`
  1629 → 1633 (the two driver flags and the menu item).
