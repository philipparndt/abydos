## Context

The root exists and works; what it is keyed on is wrong for the case somebody
actually hit. Three things as they stand:

**Which sessions get a row.** `AgentSessions.read` asks whether `scratchpad` or
`tasks` holds a non-hidden entry and sets `hasAnything` from it; `sessions(of:)`
drops the rest, and `SessionNode.build` drops them a second time once the walk
has counted files. Both are deliberate — the archived change decided that a row
leading nowhere is worse than no row, because `/tmp` is cleared on reboot and a
session's files are a thing with a lifetime. The transcript beside it is not: on
this machine this project has **fourteen transcripts and two scratch
directories**.

**When the root is read.** Once, from `load(project:)`. `reloadTree()` does not
call it, `refreshFromDisk()` does not, and the watcher is on the project's own
directory. The comment above `refreshSessions()` explains why `/tmp/claude-<uid>`
is not watched and that reasoning is untouched by this change.

**What the app already hears.** `ClaudeHookRunner.announce` posts a distributed
notification on **every** Claude Code event, with `event`, `session`, `cwd`,
`status` and — only when it is worth a toast — `announce`. `ClaudeWatch` returns
early on the ones with no `announce`, which is every `SessionStart`,
`SessionEnd`, `PreToolUse` and `PostToolUse`. The liveness signal is already
crossing the process boundary and being dropped on the floor.

There is nothing else to read it from: `~/.claude/ide/` is empty, nothing under
`~/.claude/projects/<slug>/` marks a session as running, and a `claude` process's
argv does not carry its session id, so the process table cannot be matched to a
row even if it were worth asking.

## Goals / Non-Goals

**Goals:**

- A session running in this project has a row, before it has written anything.
- The root changes while somebody is looking at it, without the project being
  reopened.
- A row never claims more than it knows: no invented size, no "running" for a
  session nobody has heard from.
- A project nobody is working in, with no files kept, looks exactly as it does
  today.

**Non-Goals:**

- Managing a live session: no stopping it, no attaching to it, no resume offered
  for one that is already running.
- A list of every Claude session on the machine, or sessions belonging to other
  projects.
- Reading the transcript as a conversation. Its head is read for a label, as
  today, and nothing more.
- Any agent other than Claude Code.

## Decisions

**A row when the session left files, or is active now — not when a transcript
exists.** Keying on the transcript is the obvious reading of "the file that
proves the session happened", and it was ruled out by counting: it would put
fourteen rows on this project where two directories still exist, twelve of them
leading to a scratchpad that went with a reboot. That is precisely the thing the
archived change decided against, and nothing has changed to reopen it. Keying on
liveness adds exactly the rows that are missing and no others.

Also ruled out: leaving the root alone and showing live sessions somewhere else —
a badge, a separate strip. It answers "is something running" and not "where did
the session I just started go", which is the question that was asked. And it puts
a second place to look for the same subject.

**Liveness comes from the hook while the app is up.** It is free, it is already
delivered, it is exact — `SessionStart` and `SessionEnd` bracket a session and
nothing has to be inferred — and it costs no directory read at all. Ruled out:
a watcher on `/tmp/claude-<uid>`, for the reason already written above
`refreshSessions()` and not weakened by anything here; and polling the process
table, which cannot say *which* session a `claude` process is, so it could light
up a row but never the right one.

**At project open, from when the transcript was last written.** There is no hook
event to have heard: the session started before the window did. The transcript is
the one file written the moment a session begins and again every few seconds
while it runs — 336 KB and growing for the session that reported this — so its
modification time is the cheapest honest proxy, one `stat` per session against
files already being looked up for the label.

It is a proxy and the row must not overstate it. **Two states, said
differently:** a session the hook has spoken for is *running*; a session known
only by a recent transcript is *active*, and its row says when it last wrote,
which is what a row already says today. Nothing is labelled "running" on the
strength of a timestamp.

Ruled out: **having the hook record live sessions in a file the app owns**, which
would survive the app restarting and need no threshold. It moves the staleness
problem rather than solving it — a session killed with `SIGKILL` never sends
`SessionEnd`, so the file needs ageing out on exactly the same guesswork — and it
adds a write to a program that runs on every tool use. `ClaudeHookRunner` already
refuses to call `waitUntilExit` there because the poll costs sixty milliseconds,
"which for a hook Claude runs on every tool use is the difference between
unnoticeable and felt". Paying for a write to fix a case the hook itself covers
is the wrong trade.

**Refreshed on the events that can change the row set, not on every event.**
`SessionStart`, `SessionEnd` and a final `Stop` change which sessions exist or
what a row says about one. `PreToolUse` and `PostToolUse` arrive dozens of times
a minute and change nothing about the set — refreshing on them would run the
measuring walk against somebody's scratchpad continuously. Plus
`refreshFromDisk()`, so a session started while the app was asleep is found when
the window comes forward.

**A hook event is this project's when the slug of its `cwd` is one of this
project's slugs**, which is the same key `AgentSessions.slugs(of:)` already
produces and already handles the `/tmp` symlink's two spellings with. Not a
prefix match: a session started in a subdirectory is filed under a different key
and genuinely has a different scratch directory, so it is not this project's
session as far as anything here is concerned.

**A row with nothing under it is a leaf, and says so.** `fileRoot(for:)` returns
the scratchpad whenever the directory exists, which for a live session means an
expandable row that opens onto nothing — a disclosure triangle is a claim that
there is something behind it. A session with no files gets no triangle until it
has one, and its subtitle says it is running rather than "0 files", which the
existing code already refuses to say before the walk has landed and must go on
refusing after.

**A driven run declines news from outside itself, and keeps a way to look.**
This is 0451 arriving by a different door. `ClaudeWatch.listensOnThisRun` already
drops news from outside the run, because a screenshot with
`● zsh · a subagent finished` in the corner is a picture that looks different for
everybody who takes it — and a *tree* with somebody else's live session in it is
the same picture, in a place `--screenshot` is pointed at far more often. The
transcript-mtime path has to answer it too, or the fix leaks in through the half
the hook does not control.

But 0451's *other* decision matters as much: it refused "no toasts on a capture
run" because that would have broken the only way to look at a toast, and broken
it silently. So the two knobs are separated — the run declines the hook and the
transcript times, and what it says about itself still counts.
`--claude-running <id>` puts one session in the register, `<id>@<seconds>` starts
it while the window is open, and those are two different claims: the first is the
read on the open path, the second is the redraw, which nothing else can drive
because the listener is off. Without it the feature could be photographed only by
being wrong.

## Risks / Trade-offs

- **The measuring walk re-firing on every refresh while a session works.**
  Counting a scratchpad is 127 ms for seven sessions and a live one is writing
  into it. → `identityForRefresh` must include liveness so the row can change
  state, while a change that is *only* liveness does not start a fresh walk; and
  the walk is not started again while one is in flight for the same sessions.

- **A row appearing and disappearing under somebody's hands.** A session that
  starts, is seen, and ends collapses whatever was expanded if the root rebuilds.
  → The existing `show(_:)` restores expansion and selection by path, and a live
  row that gains files must keep its identity rather than being rebuilt as a new
  one.

- **Hooks not installed.** Liveness then comes only from the transcript, at open
  and on window-forward. → It degrades to something rather than nothing, and this
  is worth saying out loud somewhere a person can read it, because "the row is
  late" and "the hook is not installed" look identical from the tree.

- **The `active` window is a guess.** Too short and a session somebody stepped
  away from for a coffee vanishes from the tree; too long and yesterday's
  finished sessions come back as rows leading to empty directories. → It is one
  number in one place, it only ever *adds* rows that a hook event would correct
  within seconds, and it never labels anything "running".

## What the building found

Two things the design did not have, both from driving the app rather than from
reading it:

- **A running session with no directory anywhere was never enumerated.** The ids
  came from the scratch root and the transcript listing, and a project with
  neither — which is what `--claude-running` against a fresh project is — left
  the register holding an id nothing ever asked about. The register's ids are a
  third source and have to be one.
- **And adding them inside the per-slug loop made a phantom.** A project spelled
  two ways got the id added under both, so the spelling whose directory does not
  exist produced a session with no files and a date of `distantPast` that
  shadowed the real one. Caught by `goingOnRunningIsNotAChangeOnDisk`.

## Open Questions

- **How recent is "active"?** Answered at **five minutes**, and the reasoning is
  on `AgentSessions.activeWithin`: a transcript is written on every message, so
  any window is a guess about how long somebody stares at a prompt, and the guess
  only has to survive until the next hook event. Long enough to read a diff and
  fetch a coffee; short enough that yesterday's sessions never come back.

- **Whether an ended session's row should stay put until the tree is next read.**
  Still open. A row vanishing the instant `SessionEnd` arrives is correct and may
  still be unpleasant, since that is the moment somebody looks over. It is a
  question about the redraw, not about what is true.
