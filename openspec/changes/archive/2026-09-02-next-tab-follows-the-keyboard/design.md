## Context

`selectNextTab(_:)` and `selectPreviousTab(_:)` on `MainWindowController` call
the editor unconditionally. The window already knows where the keyboard is:
`isTerminalFocused` reads `BottomPanel.hasKeyboardFocus`, and it already gates
the terminal's prior claim on control-key shortcuts. A strip click runs
`PanelTabStrip.onSelect(index)`, and the panel's handler for it knows what the
tab at that index is — the mirrored terminal, a tmux window, one of its own
sessions — and activates it with the keyboard.

## Goals / Non-Goals

**Goals:**

- ⌘⇧] and ⌘⇧[ move between the panel's tabs while the keyboard is in the panel,
  including to and from the `tmux` tab.
- The editor keeps the keys when it has the keyboard.

**Non-Goals:**

- A shortcut for tmux windows. tmux has those, and a person in tmux keeps them.
- Moving the keyboard between the editor and the panel; that is ⌘J and the
  existing focus commands.
- Cycling across columns of a split panel. The strip of the column being typed
  in is what the keys mean; the other column has its own.

## Decisions

**The existing keys, made focus-aware.** Rather than a new pair for the panel.
A second pair is one more thing to learn, and control-key pairs are the shell's
alphabet, which the app already declines to borrow while a terminal has the
keyboard. The same two keys meaning "the tabs in front of me" is what every
editor with a terminal drawer does.

*Ruled out: ⌃⇧] and ⌃⇧[ for the panel only.* For the reasons above.

**Cycling drives `onSelect`, not `activate`.** The strip computes the
neighbouring index and calls the same closure a click calls. That closure
already tells a tmux window from a session from the mirrored terminal and
focuses what it selects; a second path through the panel's model would be a
second place to keep those distinctions.

**Which strip.** The top strip of the focused column, unless it holds a single
tab and tmux's windows have a strip of their own below it — then the windows are
the tabs somebody means, and cycling steps through those. With one strip holding
everything, the tabs are the tabs.

**Wrapping.** Both directions wrap, as the editor's do.

## Risks / Trade-offs

**A menu item that means two things** → It means one thing, "the next tab where
I am typing"; the title is unchanged and the key is unchanged. Validation is not
touched: with nothing to cycle the call does nothing, as the editor's does with
one tab.

**`hasKeyboardFocus` is false while the panel is hidden** → Then the editor gets
the keys, which is right: a hidden panel is not where anybody is typing.
