## Context

The two questions, and where each is answered:

| | asked as | means |
|---|---|---|
| is this run driven | `DrivenRun.isActive` — any verb beyond `--open` and `--file` | somebody named a project on the command line and nobody is at the keyboard |
| is this a screenshot | `isScreenshotRun` — `screenshotPath != nil` | `--screenshot` was passed |

`isScreenshotRun` is asked at around twenty sites. Some of them mean the first thing
and were written when the two were indistinguishable. The comment above the follow
guard is the clearest example of the confusion, because the prose is right and only
the test is wrong:

    // Never during a capture. A screenshot is of a project somebody named
    // on the command line, and a restored tmux session whose shell sits in
    // another checkout would quietly swap it for that one — which is a
    // screenshot of the wrong program, taken without complaint.
    //
    // The sentence above was true when nobody was photographing anything
    // too, and 0509 is what it cost. The guard stays: a capture is of a
    // named project and must not follow a shell anywhere, including
    // somewhere the rule below would rightly follow it.
    guard !LaunchOptions.parse().isScreenshotRun else { return }

"A capture is of a named project" is exactly the definition of a driven run. The
comment even records that the rule was already found to be broader than photography
once, in 0509, and the test was not widened with it.

### The 0534 chain, every link of it code doing what it was asked

1. `followsTerminalProject` is `true` in the real preferences.
2. A driven run copies the real preference domain into its volatile one, so the follow
   is on.
3. The panel opens a terminal whose shell inherited a working directory that no longer
   exists. zsh says `getcwd: cannot access parent directories` and falls back to
   `~/.config/zshutil`, this machine's zsh configuration.
4. The pane reports that directory, the guard at 2039 does not fire because no
   `--screenshot` was passed, `onPaneNeedsProject` fires and `switchProject` runs.

From outside: `--print-text` prints `no editor`, `--search-steps` prints
`SEARCH: no results pane` or searches the wrong project, and `--close-window` reports
"a window showing zshutil". Nothing was typed and nothing was written, which is luck
rather than design — the switch lands *seconds after* launch, so a verb that types can
run before it and be aimed at the right file, or after it and be aimed into whatever
the terminal wandered into.

### The 0535 half

`--sidebar-shot <path>` names its own output file. Whatever it needs from behind the
gate — at minimum the project panel being skipped so nothing blocks on a modal — does
not happen, and a blank pane is written with a zero exit.

## Goals / Non-Goals

**Goals:**

- One question, asked at every site that means it.
- A driven run's project is decided once, at launch, and cannot change.
- A driven run that cannot honour `--open` fails visibly instead of substituting.
- A harness can read which project root the run opened.
- A flag naming an output produces it or refuses.

**Non-Goals:**

- Changing `followsTerminalProject` for somebody working in a window. It is a good
  feature; it simply has no meaning when nobody is making gestures.
- Redesigning the driver's flag handling. This is a gate that means the wrong thing.
- Fixing tmux sessions that outlive the directories agents make and delete. That makes
  0534 likelier — every pane on this machine reported `~/.config/zshutil`, nine
  sessions' worth — but it is the environment, not the app.

## Decisions

**Split the property rather than widen it.** Widening `isScreenshotRun` to
`screenshotPath != nil || sidebarShot != nil` is one line and fixes 0535 alone. It
does not fix 0534, and it leaves the same trap for the next capture flag. Two
properties, each named for the question it answers, is what stops this recurring:
sites asking "is this run producing a picture" and sites asking "was `--screenshot`
given" stop being distinguishable only by accident.

**Read every site before moving any of them.** This is the actual work and it is why
this is not a one-line change. A site that is right for a full screenshot and wrong
for a sidebar-only run would, if moved, trade a blank picture for a subtler wrong one
— the same failure shape, harder to notice next time.

**Suppress the follow at the gesture, not by filtering preferences.** Two ways to stop
step 4: refuse to copy `followsTerminalProject` into the volatile domain, or ignore the
pane's report while the run is driven. The second is chosen — the first is a guess
about which of some dozens of preferences are safe to carry, made one preference at a
time, and it would leave the switch reachable by any other path into `switchProject`.

**A driven run decides its project first, not fourth.** The existing guard is the
fourth branch; every fallback below it is written for somebody double-clicking the
app. A driven run wants its own decision at the top: it opens what it was given, or it
fails. That makes the rule readable in one place rather than inferable from the order
of four `else if`s.

**Failing loudly is the same argument 0522 made.** If the named project cannot be
opened, opening a different one is the worst available answer — it is the answer that
lets an agent type into somebody's real files while believing otherwise.

**Say what was opened, once.** One line naming the resolved root would have turned
0534 from an anomaly somebody noticed in passing into something a harness asserts on.
Cheap, and it makes the whole class visible.

**Refusal is the fallback for 0535, not the plan.** If reading the sites shows
`--sidebar-shot` genuinely cannot work alone, then stderr and a non-zero exit cost one
line and cannot be misread. What is not acceptable is the present state, where the
answer is a file that looks like evidence.

## Risks / Trade-offs

- **A site moved to the wrong question** → Mitigated by reading all twenty and
  recording the verdict per site, rather than sweeping them.
- **Refusing where the app used to open something** could turn a green harness run red
  → That is the point, and the red run is truthful. Worth grepping for callers that
  pass a path they expect not to exist.
- **A driven run that legitimately wants to follow a terminal** → None known, and none
  imaginable: every driver verb names its target. If one appears, it can ask for the
  follow explicitly rather than inheriting it from somebody's preferences.
- **A symlinked scratch path resolving to an already-open window** → `open(projectAt:)`
  raises an existing window for a project rather than opening a second one, and a
  scratch copy under `/private/tmp/...` reaches it through macOS's symlinked `/tmp`.
  Worth a test of its own: it is the shape that made a project under `/tmp` match none
  of its own worktrees before.
- **Another flag in the same class is missed** → Mitigated by sweeping the flag table
  once and naming what was found. This class already has two members.

## Worth knowing while working this

The app **hangs on launch with no output at all** if an earlier driven run was killed:
macOS puts up its "reopen windows?" alert from `promptToIgnorePersistentState`
*before* `applicationDidFinishLaunching`, so even `--version` prints nothing and waits
for a click nobody is there to give. `-ApplePersistenceIgnoreState YES` gets past it,
and `sample` on the hung process is what identifies it. This wastes the same hour
every time.

The way past 0534 until it is fixed: build with a bundle identifier of your own,
`make build BUNDLE_ID=…`, and seed that domain with one key first
(`defaults write <id> appearance abydos-system`) so `Settings.migrate` finds it
non-empty and does not copy the real domain in. Then `followsTerminalProject` is its
registered default of `false`. A dozen runs' worth of evidence from 0533.

## Open Questions

- Does any site behind the gate genuinely want to distinguish a sidebar-only run?
  Only reading them answers it.
- Should the "opened this root" line go to stdout or stderr? Driver verbs parse
  stdout, so a new line there may break a parser that does not expect it.
- Is there any other path into `switchProject` a driven run can reach — a menu item a
  verb clicks, a restored session — or is the pane report the only one?
