# 522. A driven run writes to real settings, real files and a restored session

> fix the harness so it stops touching my real files

The app has **191 launch-option verbs**, and they exist so that claims about the
window layer can be checked from outside — there is no test target for
`AbydosApp`, so this is the only way anything there is proved at all. They are
run dozens of times a day.

They run against the real thing. Not a double, not a sandbox: **the user's own
preferences, the user's own projects, the user's own session.** Three separate
things went wrong on one evening because of it, and none of them was a bug in
the editor:

- **A preference was destroyed.** `--switch-appearance light` reaches
  `AppDelegate.swift:1272` → `Settings.shared.appearance = …`, which writes
  `UserDefaults.standard` in the `de.rnd7.ideai` domain. An agent then ran
  `defaults delete de.rnd7.ideai appearance` trying to undo it, because it had
  not captured the old value first. The key is gone.
- **A source file was edited.** `~/dev/abydos-examples/cadova-models/Sources/coaster/main.swift`
  reads `C-ircle(diameter: diameter)` and has since 21:22:20 on 2026-08-16 — a
  minute after a driven launch, in a file nobody was editing. It fails to
  compile, so `CadovaExampleLiveTests` has been red for every agent since.
- **Characters reached a shell.** `icd ..` and `mak einstall` in the shell
  history, the same evening. **The reporter has confirmed they see the stray
  `i` during harness runs and have never once seen it in their own use** —
  which is what settles all three as the harness's doing rather than the
  editor's.

0517 spent an afternoon disproving a terminal-side explanation for the `i`, and
0521 was filed as a bug in the editor. Both were looking in the wrong place:
**the drivers type into whatever the window is showing**, and a driven launch
restores the previous session, so what it is showing is the user's own work.

## What has to become true

1. **A driven run must not write the user's preferences.** `Settings` already
   takes an injectable `UserDefaults` (`Settings.swift:36`) — `Settings.shared`
   is the only thing that hardcodes `.standard`. A volatile suite per run is
   the shape.
2. **A driven run must not type into a file it was not given.** The failure was
   a typing verb landing in a *restored* tab. Not restoring a session in a
   driven run would have prevented every one of these.
3. **A driven run must not leave anything behind** — no session file, no cache
   entry, no `.abydos` in somebody's project.

## Worth deciding

- **Whether isolation is opt-in or automatic**, and the argument is one-sided:
  every one of these happened because somebody used a verb without knowing what
  it touched. A flag that has to be remembered will be forgotten by the next
  agent. Deriving "this is a driven run" from *any* testing verb being present
  makes it impossible to get wrong, and `LaunchOptions` already computes
  `isScreenshotRun` in exactly that spirit.
- **What a screenshot of a real project does.** Some verbs exist precisely to
  photograph the app against a real checkout, so "refuse to open anything real"
  is too strong. The line is probably *writing*: read a real project, never
  write to it, and never restore a session over what was asked for.
- **Whether the settings suite is per-run or one throwaway domain.** Per-run is
  cleaner and makes runs independent; one domain is easier to inspect when a
  driver misbehaves.
- **What to do about the 191 verbs already written.** Any that write should be
  audited rather than trusted; the ones known to write are the typing family
  (`--type`, `--snippet`, `--comment`, `--emacs-nav`), `--switch-appearance`
  and anything driving a run configuration.

## Decided: automatic, and the line is writing

**Automatic.** A run is driven when it was given any `--verb` at all beyond the
two that say what to open — `--open` and `--file` — and nothing has to be
remembered by anybody. The counter-proposal is not hypothetical: the opt-in
already exists and is written down in `Scripts/bundle.sh`, which says that "an
agent building a copy to drive should use" `BUNDLE_ID=` to get a throwaway
preferences domain. Every one of the three incidents happened with that
sentence sitting in the repository. A flag that has to be remembered is a flag
that records, after the fact, who remembered it.

Deriving it from the arguments is safe in the direction it can be wrong. The
predicate only ever *adds* isolation, so a false positive costs a driven run its
ability to write to somebody's preferences — which is the whole point — while a
false negative is impossible for any verb that exists, because the rule is
"anything not on the two-item list" rather than a list of verbs to keep up to
date. A verb added tomorrow is isolated on the day it is written, without its
author knowing this file exists. `isScreenshotRun` could not have been extended
to do this: `--type`, `--emacs-nav`, `--switch-appearance` and `--run-config`
set no screenshot path, and all three incidents came from runs that took no
picture at all.

Nothing a person types can trip it. `abydos` — the command line people actually
use — passes paths and never a flag, and a launch from the Dock or from
LaunchServices passes none either. The single-dash arguments the system adds
(`-psn_…`, `-NSDocumentRevisionsDebugMode`) are not `--` and are not counted.

**The line is writing, not reading.** Some verbs exist precisely to photograph
the app against a real checkout, so a driven run still opens what it is given,
reads the real preferences, and reads the project on disk. What it may not do is
write any of it back. So the throwaway settings domain is *seeded* from the
user's own rather than started empty: a driven run should be a run of the app
somebody actually has, and one that began at factory settings would be
photographing a program nobody uses.

**Per run, not one throwaway domain.** Agents run these side by side — three
were working other items in their own worktrees while this was written — and one
shared domain makes two concurrent runs each other's problem. Per run also
answers the "leaves nothing behind" requirement without a sweep, because the
domain is a dictionary in memory that dies with the process and was never a file.

## Estimate

2026-08-17 07:57 — about four hours left

## Steps

- [x] Decide opt-in against automatic, and write the answer down
- [ ] A driven run's settings go to a throwaway domain, and the real one is
      untouched — proved by reading `defaults` before and after
- [ ] A driven run does not restore a session
- [ ] A driven run does not open a project it was not given
- [ ] A typing verb can only reach a file the run was given
- [ ] A driven run leaves nothing behind: no session file, no recents entry, no
      remembered scratches
- [ ] Audit the verbs that write, and list them in here
- [ ] Watched: the exact sequence that produced `C-ircle`, replayed, leaving the
      file untouched
- [ ] 0517 and 0521 get a line saying where the stray `i` came from
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] The spec says what the project now does

## Not part of this item

Restoring what was already damaged: the `appearance` key, the `C-ircle` line,
and the 1424 build artefacts 0518 accounted for. Those are the reporter's own
files and are theirs to put back — 0518 and 0521 carry the commands.
