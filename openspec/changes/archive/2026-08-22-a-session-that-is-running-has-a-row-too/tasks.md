## 1. What makes a session worth a row

- [x] 1.1 `AgentSession` gains how live it is — nothing, active, running — beside
      `hasAnything`, so the row rule can be read in one place. A session is worth
      a row when it left files **or** it is not `nothing`.
- [x] 1.2 `AgentSessions.read` fills the *active* case from the transcript's
      modification time, which it already stats for existence. One threshold, one
      place, named for what it is a proxy for.
- [x] 1.3 The *running* case is set from outside: `sessions(of:)` takes the set of
      session ids the hook has said are running, defaulting to empty so every
      existing caller and test is unchanged.
- [x] 1.4 `AgentSessions.measured` keeps liveness as it found it. It walks files
      and has nothing to say about whether a session is running.
- [x] 1.5 Tests: a session with an empty scratchpad and a transcript written a
      moment ago has a row; the same with a week-old transcript has none; a
      session whose id is in the running set has a row with no transcript at all;
      and fourteen transcripts against two scratch directories still produce two
      rows plus whatever is live.

## 2. Which sessions are running

- [x] 2.1 A small thing in `AbydosKit` that holds the ids of running sessions per
      project slug, fed by hook events: `SessionStart` and any working event add,
      `SessionEnd` removes. Pure, and testable by handing it events.
- [x] 2.2 It decides a hook event's project by `AgentSessions.slug(ofPath:)` over
      the event's `cwd`, matched against `AgentSessions.slugs(of:)` — exactly,
      not by prefix, since a subdirectory is filed under a key of its own.
- [x] 2.3 Tests over the real payload shapes: start then end; start with no end;
      an event from another project's `cwd`; a `cwd` spelled `/tmp` against a
      project spelled `/private/tmp`.

## 3. Telling the tree

- [x] 3.1 `ClaudeWatch` stops returning early on events with no `announce`: the
      toast still needs one, the session register does not. Keep the toast
      behaviour exactly as it is — this must not make a `PreToolUse` speak.
- [x] 3.2 It hands `SessionStart`, `SessionEnd` and a final `Stop` on to whoever
      is showing that project, and nothing else. A tool-use event updates the
      register and asks for no redraw.
- [x] 3.3 `ProjectNavigatorViewController.refreshSessions()` gains its callers:
      the events above, and `refreshFromDisk()`. Still nothing on the watcher,
      and still no watcher on `/tmp/claude-<uid>`.
- [x] 3.4 `identityForRefresh` includes liveness, so a row can go from running to
      gone — and a change that is only liveness does not start a fresh measuring
      walk. No second walk while one is in flight for the same sessions.
- [x] 3.5 The half that can be tested is tested: `RunningSessions.note` is what
      decides whether a redraw is asked for, and
      `aToolUseFromAKnownSessionAsksForNothing` is the claim that a session at
      work does not ask for one. **The navigator half is not unit-tested and
      cannot be** — `AbydosKitTests` is the only suite and the app target has
      none — so it was watched instead, which found two faults the reading had
      not (see the design). What could be moved to where it is testable was:
      `AgentSessions.rows` now holds the rule the tree used to hold a copy of.

## 4. What the row says

- [x] 4.1 `SessionNode.build` keeps a live session that measured to zero files —
      the `fileCount > 0` filter becomes "unless it is live".
- [x] 4.2 A live session with nothing under it gets no `fileRoot`, so it is a
      leaf: a disclosure triangle is a claim that there is something behind it.
- [x] 4.3 The subtitle says *running* for a session the hook spoke for and the
      time it last wrote for one known only by its transcript. Never "0 files",
      which is the lie the existing code already refuses to tell before the walk
      lands.
- [x] 4.4 The context menu offers nothing that assumes a finished session: no
      `claude --resume` for one that is already running.
- [x] 4.5 Kept is `AgentSessionRowTests`, in `AbydosKit` where it can be asked.
      Leaf, subtitle and menu are view code with no suite to hold them, and were
      driven instead against a project under the scratchpad:

          TREE rows: probe |   README.md | Claude Sessions — 1 session
                     |   aaaabbbb — running
          TREE session-menu: offers=[Reveal in Finder]

      The row is a leaf under `sessions-open-all`, which opens everything; the
      subtitle is `running` and not `0 files`; and the menu offers no
      `claude --resume` over a session that is already running.

## 5. Not on a driven run

- [x] 5.1 A driven run reads the root from files alone — both sources declined,
      the hook and the transcript time. The same question 0451 answered for the
      toast corner, asked about the tree.
- [x] 5.2 A test that a driven read produces the same rows whether or not a
      session is running, since a screenshot that varies per machine is the whole
      fault being avoided.

## 6. Finishing

- [x] 6.1 **Five minutes**, on `AgentSessions.activeWithin` with the reasoning
      beside it: the guess only has to survive until the next hook event, so it
      wants to be short rather than generous.
- [x] 6.2 Watched, against a git repository made under the scratchpad and never
      a real checkout. A driven run cannot hear the hook — that is the 0451 rule
      this change had to keep — so `--claude-running <id>[@<seconds>]` was added
      to say it, exactly as `--toast` exists to fill the corner being
      photographed:

          before      TREE roots: project=probe dependencies=absent sessions=absent
          at open     TREE roots: … sessions=1 / 0000dead [running]
          after 3 s   TREE roots: … sessions=1 / aaaabbbb [running]

      The second is the read on the open path and the third is the redraw, with
      the root absent when the window opened. **Both faults in the design were
      found here** and neither by reading it.
- [x] 6.3 `make warnings` clean, exit 0 — no warnings in this repository's Swift.
      `make test` exits 2, on two failures that are the machine and not this
      change: `ContainerImageTests` asking the Apple container runtime, whose
      `apiserver is not running and not registered with launchd`. Both report
      `XPC connection error: Connection invalid`, neither touches anything here,
      and the other 3,177 tests pass. Recorded in `.abydos/today.md`, where a
      fact about a Tuesday belongs; starting the runtime registers a launch agent
      and was not an agent's to do.

No `.abydos/backlog/spec/*.md` file is made untrue: that backlog is gone, and
what this changes is `openspec/specs/project-view/spec.md`, in the delta beside
this file.
