## Why

A mouse's side buttons do nothing in this window, and over the terminal they do
something worse than nothing.

**They were never wired.** `navigateBack` and `navigateForward` exist and work;
every caller of them is one of the two menu items — ⌘[ and ⌘] — the validator
that enables them, and a test verb. `git log -S` finds one commit that ever
touched the feature, and its message says what it added: "⌘[ and ⌘], as IDEA has
them on this platform." No mouse handling was there to break. Reported as having
worked before, which it may well have: a driver that maps side buttons to ⌘[ and
⌘] would have made it work the day that commit landed, and stop the day the
mapping changed.

**The terminal turns them into middle clicks.** This is the part with teeth:

    override func otherMouseDown(with event: NSEvent) {
        guard !mouseSelects else { return }
        _ = forwardMouse(event, button: .middle, isRelease: false)
    }

`event.buttonNumber` is never read. macOS sends `otherMouseDown` for button 2
(middle) *and* for 3 and 4 (the side buttons), so all three reach the terminal
program as button 1 — middle — and middle click in a terminal is commonly paste.
A side button pressed over the terminal can put the selection into the shell.

**And both branches swallow the event.** Neither the tracking path nor the
`mouseSelects` path calls `super`, so an unhandled side button never travels up
the responder chain. Even once the window knows what to do with one, it would
never hear about it while the pointer was over a terminal.

Nothing else in the app overrides `otherMouse*` — the editor, the tree and the
panes all let these events pass — so the responder chain is clear above the
terminal.

## What Changes

- **The terminal forwards only the middle button as the middle button.** Read
  `buttonNumber`; button 2 is middle and behaves exactly as it does today.
- **Anything the terminal does not handle goes up**, rather than being consumed.
  That is what makes a side button reachable at all, and it is also the honest
  behaviour: a view that does not act on an event should not eat it.
- **Buttons 3 and 4 navigate back and forward**, through the same
  `navigateBack`/`navigateForward` the menu items use — so the history, the
  enabling rules and the "file has been deleted since" handling are the ones that
  already exist, not a second set.
- **Handled at the window**, so it works over the editor, the tree and the panes,
  and so no view has to opt in.
- **Not proposed: forwarding side buttons to the terminal program.** The
  emulator's `MouseButton` has left, middle, right, none and the two scroll
  codes; there is no side-button code in it, and inventing one to send to
  programs that mostly do not read it is a larger change with no report behind
  it.
- **Not proposed: making the buttons configurable.** Back and forward is what
  these two buttons mean everywhere. A setting is worth adding when somebody
  wants them to mean something else.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `editor`: that the navigation history is reachable from the mouse as well as
  from ⌘[ and ⌘]. The capability describes the history and the keys; which
  gestures reach it is the same subject.
- `terminal`: which mouse buttons are forwarded to the program, and that the
  ones that are not travel up rather than being swallowed.

## Impact

- `Sources/AbydosApp/Terminal/TerminalView.swift` — `otherMouseDown`,
  `otherMouseUp` and `otherMouseDragged`, all three of which name `.middle`
  regardless of which button arrived.
- `Sources/AbydosApp/MainWindowController.swift` — where the window's responder
  chain ends up, beside `navigateBack` and `navigateForward`.
- `.abydos/backlog/spec/editor.md` and `.abydos/backlog/spec/terminal.md`.
- No new dependency, and nothing on a drawing path.
