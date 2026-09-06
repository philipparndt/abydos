## Why

**Opening a folder in this app runs code from it.** Not on a press — on the
open. The run configurations are *discovered*, which means reading a
`Makefile`, a `launch.json`, a `Package.swift` and a devcontainer definition
and being ready to launch what they name; a language server is started from
what the project's own tree provides; a terminal comes up in the project's
directory; a devcontainer is a `docker run` somebody else wrote; a commit runs
the hooks in `.git/hooks`. A repository cloned to read — a bug report's
reproduction, a dependency somebody linked, an agent's work in a worktree — is
handed the same trust as the code its owner wrote.

The sharpest edge is the one reported on 2026-09-06: **environment variables
are code**. `SOPS_AGE_KEY_CMD` is a command sops runs; `GIT_SSH_COMMAND` and
`GIT_EXTERNAL_DIFF` are commands git runs; `LD_PRELOAD` and `DYLD_INSERT_LIBRARIES`
choose what gets loaded into somebody else's process. A project-supplied `env`
in a `launch.json`, or an `.envrc` a shell sources, is arbitrary execution
wearing the clothes of configuration — and this app applies project-supplied
environment when it launches things.

VS Code answered this with Workspace Trust and it is the right shape: the
window opens, the file opens, the tree and the search and the git history all
work, and nothing runs until somebody says the project is theirs.

Asked for on 2026-09-06: "abydos shall have a untrusted mode, where no code
from downloaded projects is executed, like devcontainers. VSCode does something
similar. How can we remember the trusted projects?" — and, before it: "in the
untrusted mode, also setting environment variables must not be possible (think
of setting SOPS_AGE_KEY_CMD)".

No originating backlog item: asked for directly.

## What Changes

- **A project is untrusted until somebody says otherwise**, and says so in the
  window: a strip naming what is held back, with the one button that changes
  it. What still works is everything that is only reading — the tree, the
  editor, syntax, folding, search, the git panes and their history, diffs,
  blame, the previews this app renders itself.
- **Nothing from the project is executed while it is untrusted.** No run or
  debug configuration, no build, no test, no Make goal, no gradle or maven
  wrapper; no devcontainer and no container image the project names; no
  language server, formatter or linter, whether from the project's tree or
  chosen by it; no scheme, task or agent command the project supplies; no
  terminal in the project's directory, that being a general-purpose runner
  standing in it.
- **No environment variable the project asks for is applied to anything.**
  Not to a launch, not to a tool this app runs on the project's behalf, not to
  the terminal — because a variable is a command in every case that matters:
  `SOPS_AGE_KEY_CMD`, `GIT_SSH_COMMAND`, `GIT_EXTERNAL_DIFF`, the dynamic
  loader's. An untrusted project's `.envrc`, its `launch.json` `env` block and
  its devcontainer's `containerEnv` are read as text and passed to nothing.
- **Git writes that would run the project's hooks are named.** A commit runs
  `.git/hooks`, which is code the project carries; in an untrusted project the
  commit either declines the hooks and says so on the button, or waits for
  trust — one of those, decided in the design, and said rather than done
  quietly.
- **Trust is remembered per folder, outside the project.** A list this app
  keeps in its own Application Support, beside the recents it already keeps
  there: the folder's resolved path, when it was trusted and by which gesture.
  A *parent* can be trusted — `~/dev` once, rather than a hundred checkouts —
  because a feature that asks a hundred times is a feature answered without
  reading. Nothing about trust is ever stored inside the project: a project
  granting itself trust is the whole hole.
- **Trust can be withdrawn**, per folder and in one place, and the app returns
  to what it does with a project it has never seen.
- **Not proposed:** a sandbox. Nothing here claims a trusted project's code is
  contained once it is running — this is about what starts, not what it can do
  afterwards. Nor is it a scanner: no heuristic reads a project and decides it
  looks dangerous.

## Capabilities

### New Capabilities

- `project-trust`: what an untrusted project may and may not do, how the window
  says so, what asks and what is asked, how an answer is remembered and
  withdrawn, and the rule that a project's own files can never grant it.

### Modified Capabilities

<!-- None. `run-configurations`, `devcontainers`, `language-servers`,
`terminal` and `sops-files` each say what happens when this app is allowed to
act; trust is the gate in front of all of them, and stating it once in its own
capability is what keeps that gate from being described five times and enforced
in four. -->

## Impact

- `Sources/AbydosKit/Project/ProjectTrust.swift` — new: the store (the shape
  `RecentProjects` already has, in the same directory, with the same rule that
  a driven run never writes it), the question "is this path trusted", and the
  parent-folder rule.
- `Sources/AbydosKit/Run`, `Sources/AbydosKit/LSP`, the terminal and the
  devcontainer paths — one gate each, asked before anything is started, so that
  a new way to run something is a compile error away from being ungated rather
  than a silent hole.
- `Sources/AbydosKit/Git/Sops.swift` and everything else that builds an
  environment for a subprocess — the project's variables are dropped while it
  is untrusted, and the app's own are unaffected.
- `Sources/AbydosApp/MainWindowController` and the settings — the strip, its
  button, the sheet that asks, and the page that lists what is trusted and
  takes it back.
- No new dependency, no daemon, no scanner.
