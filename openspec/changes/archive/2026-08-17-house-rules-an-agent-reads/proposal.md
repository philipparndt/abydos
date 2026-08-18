## Why

Item 0464 made `abydos-backlog start` launch an agent, which is what it always meant
to do and had never once done. **Which makes this urgent rather than tidy:** until
then every agent was handed its item by a person who also told it how to behave in
this repository, and now the tool starts them itself.

`BacklogRunner.prompt(number:title:path:branch:)` is deliberately thin, and its
comment is right about why:

> The workflow is in `AGENTS.md` and the item is in the item. Repeating either here
> would be a second copy that drifts, and the drift would be invisible: nobody reads
> the prompt a button builds.

So the prompt points at `.abydos/backlog/AGENTS.md` and `project.md`. **Neither
contains any of the rules that actually matter on this machine**, and there is no
`CLAUDE.md` at the repository root — checked again while writing this. An agent
started by the tool today knows how the backlog works and nothing about how not to
break the machine it is running on.

From `.abydos/backlog/open/0471-an-agent-the-backlog-starts-does-not-know-the-house-rules.md`.

## What Changes

The rules below get written once, somewhere an agent reads without being told to.
Every one was learnt from an agent doing the wrong thing, and every one had to be
typed into a prompt by hand, five times in one day:

- **Never push and never publish.** An agent once created five public Docker Hub
  repositories that nobody asked for.
- **Build with a throwaway bundle id and an unpinned UUID** —
  `make build BUNDLE_ID=de.rnd7.abydos.itemNNNN PIN_UUID=0`. A build under the real
  identifier with an unpinned UUID takes the macOS Local Network grant away, which
  cost a day to diagnose. And **never `make install`**, which replaces the app
  somebody is using.
- **Never a bare `tmux` command** — always `-L <name>` or `-S <path>`, including
  kills, because `$TMUX` overrides `TMUX_TMPDIR` so it does not isolate anything. A
  killed agent destroyed the shared server twice and stopped other agents dead. The
  sessions named `abydos`, `platform`, `backlog-spec` and `check` are somebody's.
- **Guard every app launch** — assert the app opened the project asked for before
  driving it. An agent renamed a file in a real `~/.config/zshutil` because the app
  had another project open.
- **Pre-seed a throwaway defaults domain** so `Settings.migrate` does not touch real
  settings, and delete it afterwards.
- **`TestDefaults.make()`, never `UserDefaults(suiteName:)`** — enforced by
  `NamedSuiteTests`, having littered the machine with thousands of plists twice.
- **`xcrun swift`, never plain `swift`.**
- **Say what the load was under any timing**, because concurrent agents have made a
  perf test red twice in one day: `drawingIsFastEnoughToDoWhileSomebodyTypes` at
  0.605s against a 0.5s budget under load 35, and `PseudoTerminalTests` waiting 124s
  under load 65 for output that takes 0.35s.

**And the permanent are separated from today's.** "Never push" is forever. "Docker is
stopped because Apple containers are being tested" is a Tuesday. A document that
mixes them teaches an agent to distrust all of it, so they want separating — and the
temporary half wants somewhere it can be edited without a commit that reads like a
policy change.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities
- `backlog`: four requirements added. The capability already covers "A start that
  cannot launch an agent says where the work is" and "An item is picked up into a
  worktree of its own"; what it does not cover is what the agent knows once it is
  started, which is the gap 0464 opened by making `start` launch one.

## Impact

- Wherever the rules land. Four candidates and they are not equal:
  - **`.abydos/backlog/project.md`** — the prompt already names it, so it costs
    nothing to read, and it is per project. But it is *the backlog tool's* file,
    published with `backlog-spec` for other people's projects, and these rules are
    Abydos's.
  - **A `CLAUDE.md` at the root** — what Claude Code reads by itself, so it also
    covers an agent nobody started through the backlog, which is most of them. It is
    assistant-specific, and `BacklogAssistant` knows about more than one.
  - **The prompt** — exactly what that comment argues against, and the comment is
    right.
  - **A file of the project's own that `project.md` points at** — one copy, read by
    whatever reads either, and it belongs to Abydos rather than to the tool.
- `BacklogRunner.prompt`, only if the decision requires it — preferably not.
- `.abydos/backlog/spec/backlog.md`.
- Related: `driven-runs-are-not-screenshot-runs` (backlog 0534 and 0535) makes the
  "guard every app launch" rule enforceable by the app rather than only stated. A rule
  the program keeps is worth more than a rule an agent is asked to remember.
