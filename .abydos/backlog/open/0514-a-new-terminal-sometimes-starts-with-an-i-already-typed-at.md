# 514. A new terminal sometimes starts with an I already typed at the prompt

> something seems to randomely insert an "i" when you start a terminal

Reported 2026-08-16, with a screenshot, while item 508 was being worked on —
so this is written from the report and one reading of the code, not from a
reproduction. Nobody has yet made it happen on purpose, which is the first
thing to do.

Intermittent: most new terminals are clean and some come up with a stray
character sitting on the command line before anything has been typed.

## The lead, and it is a strong one

**Focus reporting.** `TerminalView.reportFocus` writes `ESC [ I` into the pty
when the view becomes first responder, and `ESC [ O` when it resigns:

    Sources/AbydosApp/Terminal/TerminalView.swift:1781
    private func reportFocus(_ hasFocus: Bool) {
        guard emulator.reportsFocus else { return }
        pty.write(hasFocus ? "\u{1B}[I" : "\u{1B}[O")
    }

`CSI I` *is* the focus-in report, and the character it leaves behind when it is
not understood is exactly an `I`. That is what makes this the first place to
look rather than one of several.

The two halves of the guess:

1. **Whose mode is it.** `emulator.reportsFocus` is mode 1004 on *this*
   emulator. tmux turns 1004 on for itself, and a pane inherits an emulator
   that may already have the mode set from whatever ran in it before — so the
   report can go out at a moment when the thing on the other end is a shell
   that never asked for it.
2. **When it is written.** A new terminal becomes first responder as it is
   created, which is while the shell is still starting. Before the shell's line
   editor is up the tty is in canonical mode with echo on, so `ESC [ I` arriving
   then is echoed and then handed to zsh, whose ZLE swallows `ESC [` as an
   incomplete binding and leaves the `I` on the line. That is precisely
   "randomly, when you start a terminal": it depends on a race between the
   focus arriving and the shell being ready.

If that is right, the fix is not to stop reporting focus — a full-screen
program genuinely wants it — but to hold the first report until the child has
asked for it in *this* session, rather than firing on a mode that was already
set.

## Worth deciding

- Whether the report should be suppressed until the child has enabled 1004
  itself since the pty was opened, rather than trusting a mode the emulator
  carried in.
- Whether a focus report should ever be written before the pty has seen its
  first output — a shell that has printed nothing has not started.

## Steps

- [ ] Make it happen on purpose — a new terminal, opened while the window is
      taking focus, with 1004 already set
- [ ] Confirm the character is the focus report and not something else
- [ ] Hold the first focus report until the child has asked for it in this
      session
- [ ] A test that fails with the old behaviour
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says when a focus report is sent
