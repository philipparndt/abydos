## 1. What the variable is called

- [x] 1.1 Read the name out of the Cadova the examples resolve —
      `cadova-models/.build/checkouts/Cadova/Sources/Cadova/Settings.swift`, and
      its release notes — rather than from any report of it, including this
      change's own proposal.
- [x] 1.2 **If there is no such variable, stop here** and say so: at `dev`
      `2408d549` there was none, and a spelling that is not the one Cadova reads
      is ignored silently, which shows up as a Finder window nobody connects to
      a typo.

      **There is none, and this is where the change stops.** Asked of the whole
      repository rather than of one file: `git log --all -p -S 'CADOVA_'` over
      every branch and tag Cadova has ever had returns three names, and they are
      all of them —

          CADOVA_LOG_LEVEL             the log severity
          CADOVA_SWEEP_DEBUG           sweep debugging
          CADOVA_TESTS_GENERATE_OUTPUT regenerating test output

      None of them touches revealing. `Settings.isFileRevealingEnabled` is a
      plain `static var` at `dev` `2408d549` — the tip of that branch and the
      revision `cadova-models` pins — and the newest tag, `0.9.1` of 2026-08-11,
      is older than the commit that introduced `Settings` at all. So there is
      nothing an environment could say to this Cadova, and setting a variable
      would be a line that does nothing until upstream grows one.
- [x] 1.3 Write down what it takes — a flag, or a word like `CADOVA_LOG_LEVEL`'s
      — and which Cadova revision first has it.

      **`CADOVA_REVEAL_FILES`**, and `0`, `false`, `no` or `off` — lowercased —
      turns revealing off. `Platform.revealingFilesDisabled` is seeded from it
      and `revealFiles` returns early on it. First in `d358a4fd`, *Read file
      reveal default from environment*, 2026-08-18, an ancestor of `dev`.

      **And 1.2's answer above was wrong.** It was asked of
      `cadova-models/.build/checkouts/Cadova`, whose `origin` is SwiftPM's bare
      mirror under `.build/repositories/` rather than GitHub — so every fetch,
      `ls-remote` and `log --all` there described a snapshot from the last
      resolve. Ask upstream about upstream. The three-variable list in 1.2 is
      what that mirror held, not what Cadova has.

      `Settings.swift` is deleted in the same commit, so
      `Settings.isFileRevealingEnabled` is gone: the examples' two lines stop
      compiling the moment they resolve a Cadova at or after it, which makes
      task 4 part of the dependency update rather than a tidy-up after it.

## 2. The app sets it

- [x] 2.1 The name spelled once, beside `CadovaModel.command`, with the value
      the run wants.
- [x] 2.2 `CadovaPreviewView.run()` sets `process.environment` to this process's
      own environment with that key added — never a dictionary of its own.
- [x] 2.3 A test in `AbydosKitTests` over whatever builds that environment: the
      key is there, and `PATH` and `HOME` survive.

## 3. Watched

- [x] 3.1 Against a scratchpad copy of the examples, never a real checkout: a
      model previewed, saved, and rebuilt, with no Finder window at any point.
      **Measured on the running process** rather than by watching for a window:
      `ps eww` on the build the preview started says `CADOVA_REVEAL_FILES=0`,
      with `PATH` and `HOME` still in it. That the guard then holds is Cadova's
      own — `Platform.revealFiles` returns early on it, read in the resolved
      checkout, with a test upstream for the parsing.
- [x] 3.2 The same with the workaround still in the model, which must also be
      quiet — the two must not fight. **Moot, and not for a good reason to
      skip a check**: `d358a4fd` deleted the `Settings` type, so a model that
      still sets `isFileRevealingEnabled` does not compile against a Cadova that
      has the variable. There is no version of this where both exist.

## 4. The examples drop the workaround

- [x] 4.1 **After 2 and 3, not before**: until the app sets the variable, that
      line is the only thing stopping the Finder.
- [x] 4.2 `Settings.isFileRevealingEnabled = false` out of
      `Sources/HexKeyHolder/main.swift` and `Sources/coaster/main.swift`, and
      the note in `Package.swift` that explains it out with them.
- [x] 4.3 In `../abydos-examples`, which is a different repository. Committed
      there, pushed nowhere.
- [x] 4.4 `ABYDOS_BUILD_EXAMPLES=1 xcrun swift test --filter CadovaExampleLiveTests`
      still green, and quiet: the suite runs `swift run` itself, without this
      app, so if it needs the variable it sets it where it starts the run.

## 5. Finish

- [x] 5.1 `.abydos/backlog/spec/previews.md` says the preview run is told not to
      reveal what it writes. Name any sentence this makes untrue.
- [x] 5.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 5.3 Write down what was ruled out: `setenv` in the app, replacing the
      run's environment, and dropping the examples' line first.
