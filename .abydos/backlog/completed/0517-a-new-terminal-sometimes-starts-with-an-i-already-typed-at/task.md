# 517. A new terminal sometimes starts with an I already typed at the prompt

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

## The lead is wrong

Measured rather than argued, four separate ways, each of which is on its own
enough. The measurements are in `images/leftovers.py`, which anybody can re-run.

**1. `ESC [ I` leaves nothing at a zsh prompt.** This is the whole premise and
it does not hold. A pty was opened, `$SHELL -l` exec'd in it with this machine's
own configuration, and `ESC [ I` written at seven different moments — 0 ms after
the fork (before the shell has even exec'd, so the bytes sit in a canonical-mode
buffer with echo on, which is the state the lead names), then 20, 50, 100, 200,
400 and 800 ms. Then `echo MARK` was typed and Return pressed. Every run
produced the same line as the control run with nothing written at all. zsh's ZLE
discards an unbound `ESC [` sequence *whole*; it does not keep the last
character. The same for `ESC [ O`, and the same again with the sequence sent
through tmux to a pane, with the pane's own mode 1004 both off and on.

**2. The character is a lowercase `i`, and the focus report is `I`.** The
report's own screenshot, and now the history file below, say `i`. `CSI I` cannot
produce one.

**3. The mode cannot be carried in from a previous session.** The emulator is
made in `TerminalView.init` — one per view — and a view starts one child. So
`emulator.reportsFocus` already means exactly what the item wanted it to mean:
*the program in this pty asked, in this session*. The one exception is
`TerminalView.startProcess`, the devcontainer path, where a second child runs in
a view that has already shown output; that is real but narrow, and what was
shown there is this app's own progress lines, which set no modes.

**4. In this machine's own setup the report is never written at all.** Settings
say `startsTmux = 1`, so every terminal is `tmux new -A -s …`; this machine's
tmux says `focus-events off`, so tmux never sends `ESC [ ? 1004 h` outward, so
`emulator.reportsFocus` is false for the whole life of the pane and
`reportFocus` writes nothing. Watched in the running app with a stand-in shell
that logs every byte arriving on the pty: across new tabs and tab switches, not
one byte was written until a focus report was deliberately provoked by turning
1004 on in the stand-in shell, and then it arrived — 9.3 s in, on a click, long
after any shell is up.

## What is actually known

The fault is real and there is hard evidence of it, from this machine's
`~/.zsh_history`:

    : 1786901557:0;icd ..

2026-08-16 21:32:37. So the `i` was genuinely in the shell's *input buffer* —
not merely drawn on the screen — and the line was submitted. (Two hours earlier,
`mak einstall` at 17:23, corrected to `make install` two seconds later. That one
reads like an ordinary typo and is not counted as evidence.)

Everything this app can write into a pty was enumerated and each was measured at
a zsh prompt, to see what it leaves when whatever asked for it has gone:

    focus in    ESC [ I          nothing
    focus out   ESC [ O          nothing
    kitty graphics reply         OK
    open reply  OSC 440          440
    primary DA                   62 1 6 22c
    secondary DA                 0 95 0c
    device status  ESC [ 0 n     n
    cell pixels ESC [ 6;19;8t    19 8t
    mode report DECRPM           1004 1
    cursor position              2 40R
    bracketed paste wrapper      the pasted text
    SGR mouse press              0 12 5M
    legacy mouse press           two or three characters

So a reply written into a pty nobody is reading *does* leave debris of exactly
this kind — `ESC [ 0 n` leaves a lone `n` — and that family is worth
remembering. But a lone lowercase `i` comes from only two inputs: a bare `i`
byte, or `ESC [ <digit> i` — media copy, the printer sequence. Nothing here
writes either, on any path: keystrokes, paste, drop, the mouse, the arrows the
wheel sends on the alternate screen, the focus report, and every reply the
emulator generates were all read and none of them can produce it.

Which is where this stops. The byte is real, it is not the focus report, and it
is not anything this app was found to write.

## One loose thread, unconfirmed

Two other stray characters turned up the same day and are written down here only
because a third instance would change where to look — none of them is evidence
on its own, and each has an innocent reading:

- `mak einstall` in the history at 17:23, corrected to `make install` two
  seconds later. Reads like an ordinary typo.
- `C-ircle(diameter: diameter)` in
  `~/dev/abydos-examples/cadova-models/Sources/coaster/main.swift`, uncommitted,
  modified 21:22 — minutes after this item was filed. A `-` inserted after the
  first character of an identifier, in the *editor* rather than a terminal.
  Almost certainly a file broken on purpose to look at diagnostics, which is
  what that fixture is for. (It also makes `CadovaExampleLiveTests` fail for
  anybody running the suite with the examples checked out beside them.)

If a stray character ever turns up in the editor with nobody having typed it,
this stops being a terminal item: it would mean a keystroke path, not a pty, and
the search would start at `TerminalView.keyDown`'s two routes — the input method
for a key with no character of its own, and the encoder for everything else.

## Worth deciding — answered

- *Whether the report should be suppressed until the child has enabled 1004
  itself since the pty was opened.* It already is. The mode lives on an emulator
  that is created with the view and destroyed with it, and only bytes from this
  pty can set it.
- *Whether a focus report should ever be written before the pty has seen its
  first output.* It cannot be, twice over: `PseudoTerminal.write` drops anything
  written while `!isRunning`, and the mode can only have been set by output that
  has already arrived and been parsed. A focus report is therefore always after
  the child's first output, by construction.

## Ruled out

- The focus report as the source of the character — four ways, above.
- "The emulator carried the mode in from a previous session" — it cannot, except
  on the devcontainer path, and there the earlier output is this app's own.
- "The report is written before the shell is up" — the write is dropped while
  the pty is not running, and the mode implies the child has already spoken.
- zsh leaving the tail of an unbound `ESC [` sequence on the line — it does not;
  it discards the sequence whole. Tested at seven arrival times and through tmux.
- tmux forwarding a focus event to a pane that did not ask — it does not, and
  with `focus-events off` it never has one to forward.
- Anything else this app writes into a pty — enumerated and measured; none
  leaves a lone `i`.
- Session restore replaying bytes into a new pane — `LaunchStore` keeps a
  terminal's name, directory and whether it was renamed, and nothing else.

## What it is waiting for

The screenshot, or the next occurrence caught with more than memory. The two
questions that would settle it:

- Is the `i` in the *input buffer* or only on the *screen*? The history line
  above says input, for that one occurrence — but a second one would confirm it,
  and a screen-only `i` would move the search to the parser instead.
- What was in the pane immediately before? Every sequence that leaves debris at
  a prompt is a *reply*, and a reply is only written because something asked.
  Knowing what had just run would name the asker.

## Steps

- [ ] Make it happen on purpose — a new terminal, opened while the window is
      taking focus, with 1004 already set
      *Not done: it does not happen. The arrangement was built — the app driven
      with a stand-in shell that turns 1004 on in its first 50 ms and logs every
      byte written to it — and across new tabs, tab switches and focus churn
      nothing was written that a shell would show.*
- [x] Confirm the character is the focus report and not something else — it is
      not, and the four measurements that say so are above
- [ ] Hold the first focus report until the child has asked for it in this
      session
      *Not done: it already does. See "Worth deciding — answered".*
- [ ] A test that fails with the old behaviour
      *Not done: nothing was changed, so there is no old behaviour. Writing a
      test to pin a guard that is already right would be a test of a claim
      nobody made.*
- [x] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says when a focus report is sent
      *Not done: no behaviour changed, and the spec says what the project does.*
- [x] Measure what each sequence this app can write leaves at a prompt, and keep
      the harness — `images/leftovers.py`

## Estimate

2026-08-16 22:02 — waiting on the screenshot or another occurrence; nothing to fix until then

## Where the `i` came from — 0522

**Not the terminal.** Everything ruled out above stands, and the afternoon spent
ruling it out was the afternoon that made the answer findable: the stand-in
shell wrote nothing, the focus report is not it, and no sequence this app emits
leaves an `i` at a prompt.

The `i` was a *driven run typing into the user's own tmux session*. A run given
a launch verb used to fall through to the most recently opened project, restore
that project's session — its terminals included — and attach to the tmux session
that project keeps. A verb that then sent keystrokes sent them into a session the
reporter was attached to elsewhere, so they arrived at their prompt: `icd ..`,
`mak einstall`. That is also why they saw it during harness runs and never in
their own use, which is the observation that settles it.

0522 closes it: a driven run does not restore a session, does not attach to a
project's tmux, and does not open a project it was not given.

## Closed without being done, 2026-08-17

Closed at the reporter's word, because 0522 found the cause and fixed it: the
harness. Every step below is left unticked, because none of them was carried
out — the answer did not come from this item's line of enquiry at all.

What is written above about what the fault is *not* stands, and cost the
afternoon it took to establish. That is the value left here.
