## 1. What to show, decided where it can be tested

- [x] 1.1 A type in `AbydosKit/Debug` that answers, for one line of text and the
      variables of a frame, which of them the line names and in what order.
- [x] 1.2 Whole tokens only: `count` matches `count`, and not `counter`,
      `account` or `discount`. Named as claims —
      `aNameIsNotFoundInsideALongerName`.
- [x] 1.3 A name occurring twice on a line is one hint, not two.
- [x] 1.4 A value with a newline in it, or longer than the budget, comes back as
      one truncated line.
- [x] 1.5 Nothing to show is answered as nothing, and costs nothing: no
      allocation for a line that names no variable.

## 2. The map, built once per stop

- [x] 2.1 The frame's variables as a dictionary by name, built when
      `onVariablesChanged` fires and thrown away when the session resumes or
      ends.
- [x] 2.2 Only the selected frame's scopes, which is what `DebugSession` already
      keeps — and the frame's own file, canonicalised the way
      `applyDebugState` canonicalises the others.
- [x] 2.3 A test that resuming clears it, since a stale value drawn over running
      code is the worst thing this feature can do.

## 3. Drawing

- [x] 3.1 `CodeView.setInlineValues(_:)` beside `setExecutionLine` and
      `setBreakpoints`, taking what to draw per line.
- [x] 3.2 Drawn after the last character of the row, dimmed, clipped at the
      view's edge, and never wrapping.
- [x] 3.3 Only rows at or above the execution line.
- [x] 3.4 One `guard` and nothing else when no session is stopped.

## 4. The wiring

- [x] 4.1 `EditorViewController.applyDebugState` carries the values the way it
      already carries breakpoints, runnable lines and the marker.
- [x] 4.2 Fed from where `onVariablesChanged` and `observeStopped` are wired
      today, so there is no second route from the debugger to the editor.
- [x] 4.3 Selecting another frame in the stack moves the values with it.

## 5. Cost

- [x] 5.1 `make timing`, with the load said beside the number: the editor still
      draws fast enough to do while somebody types, stopped and not stopped.
- [x] 5.2 If it does not hold, draw only the stopped line and say so here. It
      holds: `make timing` exit 0 at load 12.2 over 10 cores (1.2 per core), so
      nothing was narrowed.

## 6. Watched

- [x] 6.1 Against a scratchpad copy, never a real checkout: a real session
      stopped at a breakpoint, photographed, with the values beside the code.
- [x] 6.2 The same session stepped, with the values changing as it moves.
- [x] 6.3 A second file open at the same time, showing nothing.
- [x] 6.4 Resumed, and the values gone.

## 7. Finish

- [x] 7.1 `.abydos/backlog/spec/debugging.md` gains what a stopped session shows
      in the editor. Name any sentence this makes untrue.
- [x] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 7.3 Write down what was ruled out: `evaluate`, values below the stopped
      line, inline editing, and a setting.
