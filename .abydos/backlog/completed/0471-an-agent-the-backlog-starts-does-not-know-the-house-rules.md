# 471. An agent the backlog starts does not know the house rules

0464 made `abydos-backlog start` launch an agent, which is what it always meant to
do and had never once done. **Which makes this urgent rather than tidy:** until
today every agent was handed its item by a person who also told it how to behave
in this repository, and from now on the tool starts them itself.

`BacklogRunner.prompt(number:title:path:branch:)` is deliberately thin, and its
comment is right about why:

> The workflow is in `AGENTS.md` and the item is in the item. Repeating either
> here would be a second copy that drifts, and the drift would be invisible:
> nobody reads the prompt a button builds.

So the prompt points at `.abydos/backlog/AGENTS.md` and `project.md`. **Neither
contains any of the rules that actually matter on this machine**, and there is no
`CLAUDE.md` in the repository at all — checked. An agent started by the tool
today knows how the backlog works and nothing about how not to break the machine
it is running on.

## What it does not know, each of which has already gone wrong

Every one of these was learnt from an agent doing the wrong thing, and every one
had to be typed into a prompt by hand today, five times:

- **Never push and never publish.** An agent once created five public Docker Hub
  repositories that nobody asked for.
- **Build with a throwaway bundle id and an unpinned UUID** —
  `make build BUNDLE_ID=de.rnd7.abydos.itemNNNN PIN_UUID=0`. A build under the
  real identifier with an unpinned UUID takes the macOS Local Network grant away,
  which cost a day to diagnose. And **never `make install`**, which replaces the
  app somebody is using.
- **Never a bare `tmux` command** — always `-L <name>` or `-S <path>`, including
  kills, because `$TMUX` overrides `TMUX_TMPDIR` so it does not isolate anything.
  A killed agent destroyed the shared server twice and stopped other agents dead.
  The sessions named `abydos`, `platform`, `backlog-spec` and `check` are
  somebody's.
- **Guard every app launch** — assert the app opened the project asked for before
  driving it. An agent renamed a file in a real `~/.config/zshutil` because the
  app had another project open.
- **Pre-seed a throwaway defaults domain** so `Settings.migrate` does not touch
  real settings, and delete it afterwards.
- **`TestDefaults.make()`, never `UserDefaults(suiteName:)`** — enforced by
  `NamedSuiteTests`, having littered the machine with thousands of plists twice.
- **`xcrun swift`, never plain `swift`.**
- **Say what the load was under any timing**, because concurrent agents have made
  a perf test red twice in one day: `drawingIsFastEnoughToDoWhileSomebodyTypes`
  at 0.605s against a 0.5s budget under load 35, and `PseudoTerminalTests`
  waiting 124s under load 65 for output that takes 0.35s.
- **Whether a container runtime is deliberately stopped**, which is a fact about
  today and not about the repository — and is the one thing on this list that
  argues against writing all of it down as if permanent.

## Where it belongs, which is the decision

Four candidates and they are not equal:

- **`.abydos/backlog/project.md`.** The prompt already names it, so it costs
  nothing to read and it is per project, which is right. But it is *the backlog
  tool's* file, published with `backlog-spec` for other people's projects, and
  these rules are Abydos's.
- **A `CLAUDE.md` at the root.** What Claude Code reads by itself, so it also
  covers an agent nobody started through the backlog — which is most of them. It
  is assistant-specific, and `BacklogAssistant` knows about more than one.
- **The prompt.** Exactly what that comment argues against, and the comment is
  right.
- **A file of the project's own that `project.md` points at.** One copy, read by
  whatever reads either, and it belongs to Abydos rather than to the tool.

Also worth settling: **which of these are permanent and which are true today.**
"Never push" is forever. "Docker is stopped because Apple containers are being
tested" is a Tuesday. A document that mixes them teaches an agent to distrust all
of it, so they want separating — and the temporary half wants somewhere it can be
edited without a commit that reads like a policy change.

## Worth knowing

`start` prints the `cd` and the prompt whenever no agent launches, so working an
item by hand is still a first-class path — and passing `--assistant` a name that
is not installed is currently the way to get that on purpose. If the rules land
somewhere an agent reads, that stops being a workaround and becomes a choice.

## Steps

- [ ] Decide where the rules live, and separate the permanent from today's
- [ ] Write them, once, from the list above
- [ ] An agent the tool starts reads them without being told to
- [ ] Check it: start a throwaway item and see whether the agent knows a rule it
      was not given in its prompt
- [ ] Write down here what was ruled out on the way
- [ ] `spec/backlog.md` says what the project now does

## Done as an OpenSpec change

The work is in `openspec/changes/archive/2026-08-17-house-rules-an-agent-reads/`, and that change's `tasks.md` is
the record of what was done. The checklist above is left as it was written: the
work did not go through it, so nothing here was ticked from memory.
