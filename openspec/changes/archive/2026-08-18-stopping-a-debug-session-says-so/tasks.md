## 1. Reproduce it first

- [x] 1.1 Drive the reported case against a scratchpad copy of
      `abydos-examples/go-service`, never the checkout: start under the debugger,
      stop at a breakpoint, press Stop. Keep what the console shows and what the
      goroutine list shows, so the after-state is a comparison.
- [x] 1.2 Do the same for a program that exits on its own, which is the path that
      already works — the exit code reaches the toolbar there, and it is the
      behaviour the stop path has to end up matching.
- [x] 1.3 Say which adapters are to hand for checking this: Delve certainly,
      `lldb-dap` and `jdtls` if they are installed. Delve is the one that reports
      status in prose, so the others are the check that nothing was written to
      suit it alone.

## 2. Nothing of the program is left on screen

- [x] 2.1 `threads` is cleared where `stackFrames` is, on both paths — the user's
      stop and the adapter's `terminated`/`exited`.
- [x] 2.2 `onThreadsChanged` is fired, or the table keeps drawing what it last
      had.
- [x] 2.3 A test that after either path the session holds no frames, no scopes
      and no threads.

## 3. The stop reads the answer

- [x] 3.1 Send `disconnect`, then read until the adapter answers or the deadline
      passes, and only then tear down. The readability handlers currently go
      first, which is what makes the rest of this impossible.
- [x] 3.2 Off the Stop button's thread: the state goes to terminated at once and
      the draining happens behind it. `DAPClient.stop()` already carries a
      `StallWatch` note about a bounded wait on the main thread — this must not
      add a second one, and the comment should say so.
- [x] 3.3 Choose the deadline and say what it was measured against, with Delve's
      actual reply time beside it.
- [x] 3.4 A missed deadline kills the adapter as now.
- [x] 3.5 A test that the exit code from a parting sentence still reaches the
      toolbar when it arrives after the state did — the case `noteExitCode`
      already handles for a program that exits on its own.

## 4. The console says it ended

- [x] 4.1 One line when a session ends: finished, finished with a code, or
      stopped without the adapter answering.
- [x] 4.2 The words match the toolbar's.
- [x] 4.3 It is written on both paths, and exactly once.

## 5. Watched

- [x] 5.1 The reported gesture again, with the picture beside the first one: the
      console says the session ended and the goroutine list is empty.
- [x] 5.2 A program that exits on its own, unbroken.
- [x] 5.3 An adapter that will not answer — simulated rather than hoped for, so
      the deadline path is seen rather than assumed.

## 6. Finish

- [x] 6.1 A `debugging` page in `.abydos/backlog/spec/`. There is none:
      `run-configurations.md` covers what a project can run and mentions the
      debugger nowhere. Write only what this report touches.
- [x] 6.2 `make test` and `make warnings` both clean.
- [x] 6.3 Write down what was ruled out — including waiting for `terminated`
      rather than for the `disconnect` reply, and why Delve settles it.
- [x] 6.4 Say whether the last stack should survive a session, since the argument
      for keeping the goroutine list would have been the same one and was made
      for neither.
