## 1. What to show, decided where it can be tested

- [ ] 1.1 A type in `AbydosKit/Debug` that answers, for one line of text and the
      variables of a frame, which of them the line names and in what order.
- [ ] 1.2 Whole tokens only: `count` matches `count`, and not `counter`,
      `account` or `discount`. Named as claims —
      `aNameIsNotFoundInsideALongerName`.
- [ ] 1.3 A name occurring twice on a line is one hint, not two.
- [ ] 1.4 A value with a newline in it, or longer than the budget, comes back as
      one truncated line.
- [ ] 1.5 Nothing to show is answered as nothing, and costs nothing: no
      allocation for a line that names no variable.

## 2. The map, built once per stop

- [ ] 2.1 The frame's variables as a dictionary by name, built when
      `onVariablesChanged` fires and thrown away when the session resumes or
      ends.
- [ ] 2.2 Only the selected frame's scopes, which is what `DebugSession` already
      keeps — and the frame's own file, canonicalised the way
      `applyDebugState` canonicalises the others.
- [ ] 2.3 A test that resuming clears it, since a stale value drawn over running
      code is the worst thing this feature can do.

## 3. Drawing

- [ ] 3.1 `CodeView.setInlineValues(_:)` beside `setExecutionLine` and
      `setBreakpoints`, taking what to draw per line.
- [ ] 3.2 Drawn after the last character of the row, dimmed, clipped at the
      view's edge, and never wrapping.
- [ ] 3.3 Only rows at or above the execution line.
- [ ] 3.4 One `guard` and nothing else when no session is stopped.

## 4. The wiring

- [ ] 4.1 `EditorViewController.applyDebugState` carries the values the way it
      already carries breakpoints, runnable lines and the marker.
- [ ] 4.2 Fed from where `onVariablesChanged` and `observeStopped` are wired
      today, so there is no second route from the debugger to the editor.
- [ ] 4.3 Selecting another frame in the stack moves the values with it.

## 5. Cost

- [ ] 5.1 `make timing`, with the load said beside the number: the editor still
      draws fast enough to do while somebody types, stopped and not stopped.
- [ ] 5.2 If it does not hold, draw only the stopped line and say so here.

## 6. Watched

- [ ] 6.1 Against a scratchpad copy, never a real checkout: a real session
      stopped at a breakpoint, photographed, with the values beside the code.
- [ ] 6.2 The same session stepped, with the values changing as it moves.
- [ ] 6.3 A second file open at the same time, showing nothing.
- [ ] 6.4 Resumed, and the values gone.

## 7. Finish

- [ ] 7.1 `.abydos/backlog/spec/debugging.md` gains what a stopped session shows
      in the editor. Name any sentence this makes untrue.
- [ ] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 7.3 Write down what was ruled out: `evaluate`, values below the stopped
      line, inline editing, and a setting.
