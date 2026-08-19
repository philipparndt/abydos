## 1. See what the buttons actually are

- [x] 1.1 A driver verb that reports the `buttonNumber` of each `otherMouse`
      event the window sees, so what a mouse sends is measured rather than
      assumed. Drivers renumber and remap; a report saying "nothing arrived" is
      a different answer from "button 3 arrived and was ignored".
- [x] 1.2 Run it and record what the side buttons report on this machine, over
      the editor and over the terminal — the two are different paths today.
      **Measured with a hand on the mouse**: back is `button=3`, forward is
      `button=4`, and both arrive as mouse events rather than as keystrokes, so
      there is something here to fix. Over the editor only the window sees them
      — that view has no `otherMouse*` of its own and passes everything up.
      Over the terminal both layers see them, and the pane in front reported
      `tracking=true`: the program in it had asked for mouse events, which is
      the branch that used to forward a side button to it as a middle click.
      The bug was live in the pane somebody had open, not theoretical.
- [x] 1.3 Confirm the terminal case before changing it: a side button pressed
      over a program that tracks the mouse, and what reaches the program. The
      claim is that it arrives as a middle click, and it is read from the code.

## 2. The terminal stops eating them

- [x] 2.1 `otherMouseDown`, `otherMouseUp` and `otherMouseDragged` read
      `event.buttonNumber` and forward only button 2 as `.middle`.
- [x] 2.2 Everything else calls `super`, so it travels up. Both existing branches
      return without doing so, which is the half that makes the feature
      unreachable over a terminal.
- [x] 2.3 The middle button is unchanged, including that a program which is not
      tracking the mouse is sent nothing.
- [x] 2.4 A test over `TerminalEmulator.encodeMouse` that the middle button still
      encodes as it did, since that is the part with a wire format to keep.

## 3. The window navigates

- [x] 3.1 `MainWindowController` handles `otherMouseUp` for buttons 3 and 4 and
      calls `navigateBack` / `navigateForward` — the same functions the menu
      items use, not a second path.
- [x] 3.2 `otherMouseDown` for those buttons is consumed, so no stray press
      reaches anything else.
- [x] 3.3 Any other button number is passed on rather than swallowed.
- [x] 3.4 Nothing happens at the ends of the history, which `navigateBack`
      already handles by returning.

## 4. Tests as claims

- [x] 4.1 What can be decided without a window is: which button number means
      what. `theMiddleButtonIsTwoAndTheSideButtonsAreThreeAndFour`, over whatever
      small function makes that decision, so the numbering is stated once.
- [x] 4.2 The rest is the responder chain and is checked by driving, with the
      report saying what it saw.

## 5. Watched

- [x] 5.1 Against a scratchpad copy, never a real checkout: visit two places,
      then back and forward with the side buttons, reporting where the editor
      lands each time.
- [x] 5.2 The same with the pointer over the terminal, and the terminal's own
      output checked for anything pasted.
- [x] 5.3 The middle button over a program that tracks the mouse, unbroken.

## 6. Finish

- [x] 6.1 `.abydos/backlog/spec/editor.md` says the history is reachable from
      the mouse, and `terminal.md` says which buttons are forwarded and that the
      rest travel up. Name any sentence this makes untrue.
- [x] 6.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 6.3 Write down what was ruled out, including forwarding side buttons to the
      program and why the emulator settles it.
