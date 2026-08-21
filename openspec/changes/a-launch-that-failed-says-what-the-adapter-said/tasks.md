## 1. Reading the answer

- [ ] 1.1 `launch` goes through the awaited path, and its response is read —
      `DAPClient.request` already matches responses to requests for everything
      else.
- [ ] 1.2 A response with `success: false` ends the launch, carrying the
      adapter's `message` and whatever it printed.
- [ ] 1.3 The watchdog is cancelled by that report, the way a `stopped` event
      already cancels it.
- [ ] 1.4 `attach`, the same two lines and the same treatment.

## 2. What it says

- [ ] 2.1 The sentences live in `LaunchStall` beside the silent case, so both can
      be read without a window.
- [ ] 2.2 The `message` leads; what was printed follows; the console is named
      when the adapter points at it.
- [ ] 2.3 No matching on the text of a message — `success` is the fact.
- [ ] 2.4 Tests over all three shapes: a message and output, a message alone,
      output alone.

## 3. What must not change

- [ ] 3.1 The silent case keeps its sentence and its twenty-five seconds.
- [ ] 3.2 A slow build that succeeds reports nothing.
- [ ] 3.3 A test that would fail if the watchdog started reporting refusals
      again.

## 4. Watched

- [ ] 4.1 Against a scratchpad copy, never a real checkout: a Go project whose
      build fails, debugged, and the dialog read — it names the build error and
      arrives at once rather than after the wait.
- [ ] 4.2 The same project fixed, debugged, and stopping at a breakpoint —
      because a change to the launch path must not break the launches that work.
- [ ] 4.3 The delve version gate, which this machine has: dlv 1.26.2 against Go
      1.27.0 refuses with "maximum supported version 1.26". With this change the
      dialog should say that rather than `Building …`.

## 5. Finish

- [ ] 5.1 `debug-sessions` says what a refused launch reports and what the
      watchdog is still for. Name any sentence this makes untrue.
- [ ] 5.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 5.3 Write down what was ruled out, and file the two things found on the
      way: the delve version gate, and a Go module that is not at the project
      root needing the launch's working directory to be the module's.
