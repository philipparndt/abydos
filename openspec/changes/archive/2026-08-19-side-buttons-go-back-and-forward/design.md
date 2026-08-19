## Context

Three overrides in `TerminalView` handle every non-left, non-right button:

    override func otherMouseDown(with event: NSEvent) {
        guard !mouseSelects else { return }
        _ = forwardMouse(event, button: .middle, isRelease: false)
    }

and the same shape for `otherMouseUp` and `otherMouseDragged`. `mouseSelects` is
`emulator.mouseTracking == .off` — the program is not asking for mouse events —
and its comment says selection is for reading output, so a program that tracks
the mouse gets the events instead.

Two consequences, from the same two lines:

- **`buttonNumber` is never read.** macOS raises `otherMouseDown` for button 2
  and for 3 and 4. All of them are encoded as `.middle`, which is button 1 in the
  wire protocol, and a terminal program that treats middle as paste will paste.
- **Neither branch calls `super`.** Not tracking: return. Tracking but
  `forwardMouse` declines — no modifiers, or `encodeMouse` returns nil because
  the program is not tracking after all — the result is discarded. Either way the
  event stops here.

`TerminalEmulator.MouseButton` is `left = 0, middle = 1, right = 2, none = 3,
scrollUp = 64, scrollDown = 65`. There is no side-button case, so there is
nothing correct to forward even if it were wanted.

Above the terminal the chain is clear: nothing in the editor, the navigator or
the panes overrides `otherMouse*`, so those views pass these events up already.

`navigateBack` and `navigateForward` are `@objc` on `MainWindowController`, which
sits in the window's responder chain, and `validateMenuItem` gates them on
`canNavigateBack` / `canNavigateForward`.

## Goals / Non-Goals

**Goals:**

- A side button goes back or forward, wherever the pointer is in the window.
- A side button over the terminal never reaches the program as a middle click.
- The middle button goes on behaving exactly as it does now.
- One history, one set of rules about when a step is possible.

**Non-Goals:**

- Sending side buttons to terminal programs. The emulator has no code for them.
- A setting for what the buttons do. Back and forward is what they mean.
- Changing ⌘[ and ⌘], or the history itself.
- Touching the left and right button paths, which are a different set of
  overrides with their own tmux-menu behaviour.

## Decisions

**Button 2 is the middle button; 3 and 4 are back and forward.** That is the
macOS numbering — `otherMouseDown` covers everything past left and right, and
`buttonNumber` says which. Drivers can renumber or remap, so this is what the
system reports rather than a claim about anybody's hardware.

**The terminal reads the number and forwards only the middle one.** The
`mouseSelects` guard stays as it is for the middle button: a program that is not
tracking the mouse should not be sent one. Everything else calls `super` and
travels up.

**A view that does not act on an event does not eat it.** Both existing branches
return without calling `super`, which is why nothing above the terminal can ever
see these buttons. That is the actual defect behind "it does nothing over the
terminal", and it is worth stating separately from the middle-click bug because
fixing one without the other leaves the feature half-working in the pane people
have open most.

**Handled at the window, not per view.** `MainWindowController` is in the
responder chain and already owns `navigateBack`/`navigateForward`. Putting it
there means the editor, the tree, the panes and the terminal all get it without
any of them opting in — and a view that *wants* a side button for something else
can still take it by overriding, which is how the responder chain is meant to
work.

**Acted on release, not press.** A navigation changes what is on screen, and a
button held down while the hand is still deciding should not have moved
anything — the same reason a click is a press and a release in one place.
`otherMouseDown` is consumed for those buttons so nothing else sees a stray
press, and `otherMouseUp` is what navigates.

**Nothing happens when there is nowhere to go.** `navigateBack` already returns
without doing anything when the history has no earlier place; that is the same
check the menu item's enabling uses, and it needs no second implementation. A
button that does nothing at the end of the history is what a browser does.

## Risks / Trade-offs

- **Calling `super` from the terminal's mouse handlers changes what other
  buttons do**, not only the side ones. → Only the paths that do not forward are
  changed. What is forwarded today is forwarded after, and the middle button's
  behaviour is asserted rather than assumed.
- **A driver that reports side buttons as something else** — some map them to
  key strokes instead, in which case nothing arrives as a mouse event at all. →
  Then this changes nothing for that mouse, which is the correct outcome; the
  driven check reports the button numbers actually seen so the two cases can be
  told apart.
- **Middle-click paste, for anybody relying on it.** → Unchanged: button 2 still
  forwards exactly as it does today.
- **A side button while a terminal program tracks the mouse** now navigates
  rather than being swallowed. → That is the point, and it is the same rule the
  rest of the window follows. A program that genuinely wants those buttons cannot
  be told about them anyway, since the emulator has no code for them.

## Open Questions

- Should a side button over a **terminal running a full-screen program** be
  reserved for that program instead? It cannot be delivered today, so the
  question is only whether to swallow it. Proposed: no — a gesture that works
  everywhere except one pane is a gesture people stop trusting.
- Do buttons beyond 4 exist on anybody's mouse here, and should they do
  anything? Left alone: they travel up and nothing claims them, which is what
  happens to an unhandled event everywhere else.
- Should the *tree* have its own back and forward, for folder navigation? A
  different history and a different question; named because a side button
  pressed over the tree will now move the editor, which is worth watching.
