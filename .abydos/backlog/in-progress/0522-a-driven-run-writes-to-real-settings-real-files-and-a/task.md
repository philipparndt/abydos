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

2026-08-17 08:31 — done, bar the push

## Steps

- [x] Decide opt-in against automatic, and write the answer down
- [x] A driven run's settings go to a throwaway domain, and the real one is
      untouched — proved by reading `defaults` before and after
- [x] A driven run does not restore a session
- [x] A driven run does not open a project it was not given
- [x] A typing verb can only reach a file the run was given
- [x] A driven run leaves nothing behind: no session file, no recents entry, no
      remembered scratches
- [x] Audit the verbs that write, and list them in here
- [x] Watched: the exact sequence that produced `C-ircle`, replayed, leaving the
      file untouched
- [x] 0517 and 0521 get a line saying where the stray `i` came from
- [x] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [x] The spec says what the project now does

## The audit: which of the 191 verbs write

All 191 `case "--…"` in `LaunchOptions.parse`, read against what acts on them.
The count is 25 + 9 + 9 + 9 + 32 + 107 = 191, which is the number in the title of
this item and the number `grep -c 'case "--'` gives.

The item guessed the typing family, `--switch-appearance` and "anything driving
a run configuration". It was right about all three and it was a small fraction
of the answer.

**Write a source file or the project (25).** `--type`, `--type-block`,
`--indent-block`, `--comment`, `--comment-key`, `--snippet`, `--complete`,
`--undo-tree`, `--emacs-nav` (⌃K kills a line, ⌃O opens three),
`--report-typing` (types real keystrokes into the open file), `--rename`
(commits the LSP workspace edit — *every affected file on disk*),
`--external-edit` (rewrites the open file from outside), `--new-file`,
`--new-folder`, `--tree` (its script has `new:`, `rename:`, `cmd-delete`,
`paste`, `drop:`, `export:` and `type:` in it), `--changes-tree` (`stage:` and
`unstage:` rewrite `.git`'s index), `--backlog-new`, `--backlog-init`,
`--make-run`, `--make-goal`, `--make-debug`, `--save-config` (all four write a
configuration into `.abydos/run/`), `--export` (writes the picture *beside the
diagram source*, one per fence for markdown), and `--open`/`--file` — which are
the two that are *not* driving, and therefore the two that still write the
recents list and the project's session on quit, which is the point of them.

**Write a preference (9).** `--zoom`, `--theme`, `--switch-appearance`,
`--appearance-walk`, `--wrap`, `--zoom-cycle`, `--untmux`, `--choose-setting`,
and `--lsp-banner ignore`. Every one now lands in the throwaway store.

**Write elsewhere on disk (9).** `--screenshot` (and the `-sheet` and `-childN`
files beside it), `--sidebar-shot`, `--metal-shot`, `--toolbar-image`,
`--toolbar-location`, `--tab-close-hover`, `--stall` and `--probe-lan` (both to
`~/Library/Logs/Abydos/`), and `--scratch` — which creates a note under
`~/.config/ideai/scratch/`.

**Type into a terminal, and so possibly into a shell somebody is in (9).**
`--run`, `--send-bytes`, `--dead-key`, `--option-key`, `--type-latency`,
`--tmux-add`, `--tmux-close`, `--tmux-drag`, `--tmux-menu`. This is the family
behind the `icd ..` in the reporter's history, and what closes it is not a guard
on any of them: a driven run opens only a project it was given, so the tmux
session it attaches to is that project's and not the one somebody is standing in.

**Run a program, and so write whatever that program writes (32).**
`--terminal`, `--tab-add`, `--terminal-tab-key`, `--bell`, `--bench-render` and
the five `--split*`/`--tearoff-terminal`/`--terminal-drop-preview` verbs all fork
a login shell. `--review` and `--review-uncommitted` start a Claude Code agent,
which may edit anything in the tree. `--push` and `--push-branch` push to a
remote. `--run-line`, `--debug-line`, `--run-config`, `--rerun`, `--launch-run`,
`--launch-debug`, `--launch-profile`, `--launch-menu`, `--debug-steps`,
`--debug-inspect` and `--debug-binary` build, run or debug. `--devcontainer`,
`--press-devcontainer-menu` and `--answer-toast` can bring a container up and
store the consent. `--stop-running` signals a language server and removes its
container. `--pods` and `--pod-profile` reach a cluster.

**Read only (107).** The remainder, listed in the audit and not repeated here.
Four groups of them are read-only only *because* of this item, which is worth
saying: `--breakpoint*`, `--bp-*` and `--launch-config` would have gone into the
project's `session.json`; and `--window-size`, `--resize`, `--zoom-window`,
`--panel-height`, `--sidebar-width`, `--settings-divider` and `--editor-divider`
would have moved the autosaved window and split frames in the reporter's own
preferences. Both are inert now, and neither was inert on the evening this item
describes.

### Two the guard does not cover, written down rather than fixed

- **`--comment-key`** reaches the document through
  `NSApp.mainMenu?.performKeyEquivalent` rather than through a driving helper,
  so `codeViewToDrive` never sees it. It cannot be guarded there without
  guarding ⌘/ for the person using the app. What protects it is the structural
  half: there is no tab in front that the run did not open.
- **`--scratch`** leaves a note in `~/.config/ideai/scratch/`. It is the one
  thing a driven run still leaves behind, it is the verb's whole purpose, and
  sending it somewhere else would break `--scratches` and `--open-scratch`,
  which exist to look at what is there. Worth an item of its own if the notes
  folder starts filling up with them.

## What a driven run touches now

| | before | now |
|---|---|---|
| preferences | `UserDefaults.standard`, `de.rnd7.ideai` | a dictionary in memory, seeded from that domain, gone with the process |
| the window frame and split positions | AppKit autosaved them into that domain | frame read once by name, nothing saved |
| the session beside a project | restored, and written back on switch and on quit | neither |
| the project, when none was named | the most recently opened one | none |
| the recent-projects list | written | held in memory, not written |
| which scratches were open | an `openScratches.<project>` key per project | in memory |
| the file a typing verb reaches | whatever was in front | a file the run named, or a refusal by name on stderr |
| the tmux session | the project's own, which the user may be attached to | only a project the run was given, so only a session of its own |

Unchanged on purpose, because these are what the verbs are *for*: a run still
reads the real preferences, still opens a real checkout when it is given one,
still writes the PNG or the SVG it was asked for, still creates the file or the
folder a verb exists to create in a project it was given, and still runs
programs. The line is writing to things nobody asked it to write to.

## Found on the way, and ruled out

- **`UserDefaults(suiteName:)` cannot do this, and the item's suggestion of a
  "volatile suite" would have failed quietly.** A suite is *added to* the
  standard search list rather than replacing it, and the app's own domain sits
  in front of it: a driven run would write `appearance` into the suite, read it
  back from the user's domain, and so both fail to change the setting it was
  asked to change and go on answering with the real one. `VolatileDefaults` is
  an `NSUserDefaults` subclass instead, which is what the subclassing notes
  describe. Its typed accessors are overridden as well as the primitives —
  `bool`, `double`, `stringArray` and the rest are *documented* as built on
  `object(forKey:)`, and a single one that was not would be a silent hole in
  exactly the thing this is for.

- **The recents fallback, not the session, is what pointed the run at
  `abydos-examples`.** The item and 0521 both had the session as the whole
  cause. It is half: `AppDelegate` fell through to `RecentProjects.shared
  .entries.first` when no project was named, so a verb run with no `--open`
  opened whatever the reporter had last worked in — and *then* restored its
  session over that. Either one alone would still have put a stranger's file in
  front of a typing verb.

- **The stray `i` reached the shell through tmux, and that is why 0517 could
  not find it.** 0517 looked for something the terminal *emitted*. Nothing did.
  A driven run restored the project's terminals, which attach to the tmux
  session that project keeps — the same session the reporter was attached to in
  their own terminal — so a keystroke sent to the app's pane arrived at their
  prompt. `icd ..` and `mak einstall` are a keystroke landing between two
  characters of something being typed somewhere else entirely.

- **AppKit writes preferences that no injected store can intercept, and the
  replay is what found it.** With the source file byte-identical, the session
  untouched and `appearance` still absent, `defaults read de.rnd7.ideai` had
  still moved: `NSSplitView Subview Frames IdeaiSplit`, `… IdeaiPanelSplit` and
  `NSWindow Frame IdeaiMainWindow` are written by the framework itself, under
  the autosave name the view is given. A driven run is given none. This is the
  answer to "leaves nothing behind" that reading the code would never have
  produced.

- **Not done: `TmuxSettings.migrateAwayFromConfigEdit()` still edits
  `~/.tmux.conf` on a driven run.** It is a one-time migration that removes a
  line an old version added, it is idempotent, and it is the same thing the
  installed app does on its next launch anyway — so isolating it would mean a
  driven run leaving a repair undone rather than avoiding a change. Written down
  because it is the one write to a file of the user's that a driven run still
  makes.

- **Not done: no test for `LaunchOptions`.** There is no test target for
  `AbydosApp` — that is the reason the 191 verbs exist at all — so the parsing
  and `givenPaths` are checked only by running the app. What could be moved was
  moved: the rule about which file a typing verb may reach is
  `DrivenRun.mayType` in `AbydosKit`, where the suite asks it the two questions
  that matter, including the exact shape of the run that produced `C-ircle`.

- **A neighbour made the `defaults` proof harder than it should have been.**
  Two before/after pairs came back with the split frames moved, and it was not
  this build: another agent was driving an *unfixed* build from the 0523
  worktree at the same time (`ps` named it), and the values oscillated between
  its shape and the user's own window's with no run of mine in between. A third
  pair, with `--type`, `--switch-appearance dracula` and `--sidebar-width 320`,
  came back `IDENTICAL`. Anybody repeating this should check `ps` first.

## The replay

A copy of `cadova-models` under `/private/tmp`, with `Circle(diameter:
diameter)` in `Sources/coaster/main.swift` and an `.abydos/session.json` naming
that file as the one that was open — the exact shape of the run that produced
`C-ircle`: a typing verb against a project with a session to restore.

    Abydos --open <copy> --type "C" --switch-appearance dracula \
           --sidebar-width 320 --screenshot <png> --delay 5

Afterwards: `main.swift` byte-identical (`d78c3c12…` before and after),
`session.json` byte-identical, no file added to the project, and
`de.rnd7.ideai` identical across the run — with `appearance` still absent, which
is the sharpest probe available because the key is missing and `--switch-appearance`
would have created it.

And the control, so that the fix is not simply the harness being broken: the
same project with the file *named* —
`--open <copy> --file a.swift --type "ZZ" --print-text` — prints `| ZZlet a = 1`.
A run that says which file it means still types into it.

### Proving the geometry, with a neighbour running

Diffing the whole domain either side of a run is unreliable on a machine where
the reporter's own app and other agents' unfixed builds are writing the same
three keys. The way round it is to give the run a shape nothing else has:

    Abydos --open <copy> --file a.swift \
           --window-size 903x707 --sidebar-width 333 --panel-height 211 \
           --screenshot <png> --delay 6

Afterwards `903`, `707`, `333` and `211` appear nowhere in the geometry keys of
`de.rnd7.ideai`, which still hold the reporter's 1880-wide window, their 260pt
sidebar and their 258pt panel. A run whose window was 903×707 wrote no window
frame and no split position, and that conclusion does not care what else on the
machine is running.

### The whole session, key by key

`de.rnd7.ideai` held 210 keys before any of this and 211 after every run above.
The one addition is `openScratches.9fe884126e2fad13`, and it was already there in
the snapshot taken *before the first build* — the reporter's own app, or the
neighbour, opening a scratch while this was being written. No run here added a
key, and `appearance` is still absent, which it would not be if
`--switch-appearance dracula` had reached the domain any of the four times it was
run.

## Not part of this item

Restoring what was already damaged: the `appearance` key, the `C-ircle` line,
and the 1424 build artefacts 0518 accounted for. Those are the reporter's own
files and are theirs to put back — 0518 and 0521 carry the commands.
