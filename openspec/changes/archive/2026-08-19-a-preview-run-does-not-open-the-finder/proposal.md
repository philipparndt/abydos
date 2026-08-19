## Why

Cadova reveals what it writes. `Model.swift` ends a build with

    try? Platform.revealFiles([url])

and `Platform.revealFiles` opens the Finder unless `Settings.isFileRevealingEnabled`
has been turned off. That is right for somebody running `swift run` in a
terminal and wrong for this app, which runs the same command on every save of
any of the target's sources — so a preview that redraws itself would bring the
Finder to the front each time.

**The examples pay for it in the wrong place.** `cadova-models`, the package the
live tests build, carries the workaround in the models themselves:

    Sources/HexKeyHolder/main.swift:28: Settings.isFileRevealingEnabled = false
    Sources/coaster/main.swift:14:      Settings.isFileRevealingEnabled = false

Two example programs are written around a host that has not asked for anything.
The line is not about the model, it is about who is running it — and every new
example has to remember it, or the Finder comes back.

**Cadova is reported to support an environment variable for this now**, which
moves the setting to where the fact belongs: the process that starts the run
says how it wants the run to behave, and the model says nothing at all. Cadova
already seeds `Settings.logLevel` from `CADOVA_LOG_LEVEL` exactly this way.

**One thing is unverified and is treated as unverified rather than guessed.** At
the revision the examples resolve — `dev` at `2408d549`, 2026-08-17, which is
also that branch's tip — `isFileRevealingEnabled` is a plain `static var` with no
environment seeding, and `CADOVA_LOG_LEVEL` is the only `CADOVA_*` name in the
tree. So the variable's name is not written into this proposal. Reading it out
of the resolved Cadova is the first task, and it is the task the rest depends
on.

Reported in conversation. No `.abydos/backlog` item was filed for it.

## What Changes

- **The preview run says it does not want the Finder.** The environment Cadova
  reads for this is set on the `swift run` that `CadovaPreviewView` starts, so
  every model previewed in this app behaves the same way whether or not its
  author thought about it.
- **The variable is named in one place**, beside `CadovaModel.command`, rather
  than as a string in a view.
- **The examples drop the workaround.** `Settings.isFileRevealingEnabled = false`
  comes out of `HexKeyHolder` and `coaster`, and the note in that package's
  `Package.swift` that explains why it is there comes out with it. **That is a
  change to `../abydos-examples`, a different repository**, and it is made
  there — not pushed anywhere.
- **The examples' own runs keep behaving.** `CadovaExampleLiveTests` builds and
  runs that package through `swift run` without this app; with the workaround
  gone, whatever the test harness needs is set the same way the app sets it.
- **Not proposed: dropping the workaround before the app sets the variable.**
  The order matters — the wrong order is a Finder window per save for anybody
  who previews an example in between.
- **Not proposed: setting `CADOVA_LOG_LEVEL` while we are here.** A different
  setting, no report behind it, and the run's output is read for the path it
  printed — quieting it is a change to something that is working.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `previews`: "A Cadova model is built and run to be seen" describes the run
  this app starts. That the run is told not to reveal what it writes is part of
  what the run is.

## Impact

- `Sources/AbydosKit/Project/CadovaModel.swift` — where `command` is spelled, and
  where the environment for a run belongs beside it.
- `Sources/AbydosApp/Editor/CadovaPreviewView.swift` — `run()`, which builds the
  `Process` and today sets no environment at all, so it inherits the app's.
- `../abydos-examples/cadova-models` — two `main.swift` files and a note in
  `Package.swift`. A separate repository, changed there.
- `.abydos/backlog/spec/previews.md`.
- No new dependency. The Cadova version the examples resolve may have to move
  forward, which is that package's `Package.resolved` and not this one's.
