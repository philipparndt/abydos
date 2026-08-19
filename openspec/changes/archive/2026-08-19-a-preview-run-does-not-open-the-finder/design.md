## Context

`CadovaPreviewView.run()` builds the process itself:

    let invocation = UserShell.invocation(for: model.command)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: invocation.executable)
    process.arguments = invocation.arguments
    process.currentDirectoryURL = model.packageDirectory

`process.environment` is never set, so the run inherits the app's environment
whole — which is why an environment variable is enough to change what the run
does, and why setting one is a single assignment rather than a mechanism.

`model.command` is `swift run <product>`, spelled in `CadovaModel`, and the run
goes through the user's login shell for the same reason everything else does:
a toolchain a version manager owns is not on a Dock-launched app's `PATH`.

On the Cadova side, `Platform.revealFiles` is guarded by
`Settings.isFileRevealingEnabled`, and `Settings.logLevel` is seeded from
`CADOVA_LOG_LEVEL` at process start. That is the shape an environment variable
for revealing would take, and the shape this change is written against.

## Goals / Non-Goals

**Goals:**

- A preview rebuild never brings the Finder forward.
- The fact lives with the process that starts the run, not in the model.
- The examples stop carrying a workaround for a host they know nothing about.

**Non-Goals:**

- Changing what the run is (`swift run <product>` in the package root) or how
  its output is read.
- Any other Cadova setting.
- Pushing anything to the examples repository or to Cadova.

## Decisions

**The variable is `CADOVA_REVEAL_FILES`, and `0`, `false`, `no` or `off` turns
revealing off.** Read from `Platform.swift` on `dev`, where
`Platform.revealingFilesDisabled` is seeded from it and `revealFiles` returns
early on it. Added by `d358a4fd`, *Read file reveal default from environment*,
2026-08-18 — an ancestor of `dev`, whose tip is two commits further on.

**How this was nearly got wrong is worth writing down.** The first search for
the name was run in `cadova-models/.build/checkouts/Cadova`, and *that
checkout's `origin` is not GitHub* — it is SwiftPM's own bare mirror under
`.build/repositories/`, which only moves when the package is resolved again. So
`git fetch`, `git ls-remote` and even `git log --all` there answer for a
snapshot rather than for the repository, and the answer they gave was that no
such variable had ever existed. **A local checkout of a dependency is a cache,
not the upstream**, and a question about what upstream has must be asked of
upstream.

**`Settings` is gone in that same commit**, which turns the examples' half from
tidying into a requirement: `Settings.isFileRevealingEnabled` no longer exists,
so a `cadova-models` that resolves a Cadova at or after `d358a4fd` does not
compile until those two lines are removed. Updating the dependency and removing
the lines are therefore one change, not two.

**Set on the run, not on the app.** `setenv` in the app would reach every
subprocess it ever starts, which is a language server, a build, a container and
a shell. `process.environment` for the one run says exactly as much as is true:
*this* invocation does not want the Finder.

**Set through `process.environment`, not by prefixing the command with `env`.**
`BottomPanel.runCommand` builds an `env NAME='value' …` line because it is
handing a string to a shell in a terminal; here there is a `Process` in hand and
a dictionary is what it takes. One less quoting problem.

**Inherit and add, never replace.** `process.environment = [name: value]` would
hand the run an environment with no `PATH`, no `HOME` and none of the
toolchain's own variables. It is `ProcessInfo.processInfo.environment` with one
key set.

**Kept even after the examples drop their line.** The app sets it for every
Cadova model anybody previews, not only for ours — a model from somebody else's
repository has no reason to know this app exists, which is the whole point of
moving the setting out of the models.

**The examples change second.** Until the app sets the variable, the line in the
models is the only thing stopping the Finder. Removing it first is a Finder
window per save for anybody who previews an example in between.

## Risks / Trade-offs

- **Cadova may not have the variable at all**, in which case there is nothing to
  set. → The first task finds out, from the resolved source rather than from a
  report; the change stops there and says so rather than shipping a spelling
  that does nothing.
- **The name may change before Cadova tags a release** — the examples track
  `dev`, which is a branch. → It is spelled once, beside `command`, so a rename
  is one line; and the check that it works is a run, not a constant.
- **A model that turns revealing back on in code** — `Settings` is a `var` and
  the last write wins. → Nothing can be done about that from outside the
  process, and nothing should be: a model that asks for the Finder explicitly is
  asking.
- **The examples' live tests** run `swift run` themselves, without this app. →
  They are the reason the examples change is a change and not a deletion: what
  the harness needs is set where the harness starts the run.

## Open Questions

- **Should the examples pin a newer Cadova as part of this?** They must, to have
  the variable at all — and the same update removes the API their two lines
  call, so it is that change or neither.
- **Should `CadovaExampleLiveTests` set the variable too**, so that a test run
  never reveals either? It runs `swift run` in a subprocess of the suite, so it
  can — worth doing if the answer to the first question makes it possible.
