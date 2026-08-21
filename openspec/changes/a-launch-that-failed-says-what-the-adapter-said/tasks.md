## 1. Reading the answer

- [x] 1.1 Not the awaited path, and the reason is in the code's own comment: the
      adapter answers `launch` only once configuration is done, so awaiting it
      would block the events that finish the launch. **"Not awaited" had been
      written as "not read"** — `send` takes a completion and nobody passed one.
      One `send(_:watching:)` helper does, and the request is still not waited
      on.
- [x] 1.2 A response with `success: false` ends the launch, carrying what the
      adapter said and whatever it printed. The client already turned a refusal
      into `.adapterError`; nothing was listening.
- [x] 1.3 The watchdog cannot double-report: the refusal sets the state to
      `terminated`, and the watchdog only fires while `starting`. The generation
      is checked too, so a refusal from a launch somebody has already replaced
      says nothing.
- [x] 1.4 All four sends, not two: `launch` twice (the generic path and the
      exec-mode one) and `attach` twice (a pid, and the gdbserver path). Each was
      fire-and-forget.

## 2. What it says

- [x] 2.1 `LaunchStall.explainRefusal` sits beside `explain`, so the refused and
      the silent case can both be read without a window.
- [x] 2.2 The adapter's sentence leads, what it printed follows, and the console
      is named only when the adapter pointed at it.

      **And the sentence had to be got from the right field**, which the driving
      found: for a build that *succeeds* and a launch that is then refused,
      delve sends `message: "Failed to launch /path"` and puts the reason in
      `body.error.format` — "Version of Delve is too old for Go version go1.27.0
      (maximum supported version 1.26…)". Keeping `message` alone reported a
      path where a fault was available. `DAPClient.refusal` prefers the field the
      protocol means to be shown.
- [x] 2.3 No matching on the text of a message — `success` is the fact, and the
      only text this reads is the one it shows.
- [x] 2.4 Tests over all four shapes — a message and output, a message alone,
      output alone, and neither — plus an attach, which says it was an attach.

## 3. What must not change

- [x] 3.1 The silent case keeps its sentence and its twenty-five seconds,
      untouched; its own suite still passes.
- [x] 3.2 A launch the adapter accepts reports nothing — held by the live test
      that passes either way: where delve matches the installed Go the launch is
      accepted and nothing is said.
- [x] 3.3 The live suite is that test, and it is a clock: the refusal is
      asserted to arrive in under twenty seconds against a watchdog that waits
      twenty-five, so anything reported by the watchdog fails it. Measured at
      **0.1 s** for a failed build and **0.5 s** for a refused launch after a
      good one. It also asserts the message is not the watchdog's — no
      `DevToolsSecurity`, no "stopped without starting".

## 4. Watched

- [x] 4.1 Against a scratchpad project, never a real checkout: a Go module whose
      build fails, debugged through the app. The report:

          The debugger would not start the program: Failed to launch: Build
          error: Check the debug console for details.
          Build Error: go build -o …
          ./main.go:4:2: undefined: noSuchFunctionAnywhere (exit status 1)
          The debug console has the whole of it.

      The compiler's own line, at once, where there used to be `Building …`
      twenty-five seconds later.
- [ ] 4.2 **Not done, and not doable on this machine.** A launch that works
      cannot be watched here at all: delve 1.26.2 refuses every Go 1.27.0 binary,
      so the fixed project takes the refusal branch too (4.3 is that run). What
      covers the accepted path is the live test, which passes either way and
      asserts that nothing is reported when the adapter accepts — on this machine
      it took the refusal branch, so **the accepted branch is unwatched**. It
      wants a re-run once delve is updated.
- [x] 4.3 The delve version gate, through the app, on a project that builds:

          The debugger would not start the program: Failed to launch /…/gogood:
          Version of Delve is too old for Go version go1.27.0 (maximum supported
          version 1.26, suppress this error with --check-go-version=false)

      Which is the reported fault, named. Before this change the same run said
      `Building …` and nothing else.

## 5. Finish

- [x] 5.1 `debug-sessions` says what a refused launch reports and what the
      watchdog is still for. **Nothing existing is made untrue**: the capability
      had five requirements — a session that ended, the console saying so,
      stopping waiting for the answer, variables beside the code, and a value
      that opens — and none of them says anything about a launch that failed.
      The watchdog's own behaviour is unchanged and now has a scenario saying so,
      which it did not have before.
- [x] 5.2 `make test` and `make warnings`, both clean, exit codes trusted.
      `make test exit=0` — 3135 tests in 414 suites, 2 known issues, load 10.8
      over 10 cores. `make warnings exit=0`, four warnings and all four in
      vendored tree-sitter C.
- [x] 5.3 What was ruled out, and what was corrected:

      - **Awaiting `launch`.** The comment in the code was right: the adapter
        answers it only once configuration is done, so awaiting it would block
        the events that finish the launch. The fix is a completion, not an await.
      - **Shortening the watchdog** to make refusals feel faster. It would make a
        thirty-second build look like a failure, which is this fault in reverse.
      - **Reporting on the `terminated` event.** Delve never sends `exited`, and
        `terminated` after a failed launch cannot be told from a program that ran
        and stopped. The response says which happened.
      - **Matching the text of a message.** "Build error", "exec format error" —
        wordings, and one adapter's at that. `success` is the fact.
      - **Parsing the build error** to say something shorter. Whatever the
        compiler said is the clearest thing available.

      **A correction to this change's own proposal.** It said a Go module that is
      not at the project root probably needed the launch's working directory to
      be the module's, and named that as the likeliest reason the reported build
      failed. That is wrong: `DebugSession.launch` already uses the *program's*
      own directory, with a comment saying why — "a build only works from inside
      its module or its package and the project root often is neither" — so a
      module in `app/` is already handled. The reported failure was the delve
      version gate, which 4.3 now shows named.

      Still worth its own item, and not this one's business: **this machine
      cannot debug Go at all** until delve is updated, which is why 4.2 has no
      watched run behind it.
