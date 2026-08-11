# 451. A documentation screenshot catches whatever toast the machine happens to raise

`Scripts/screenshots.sh` says at the top that it is reproducible on purpose:
the window is given a size, the panel a height, and each project is copied to a
temporary directory, because anything remembered per machine is a picture that
looks different for everybody who takes it. One thing was missed, and it was
found while taking the `diagram` shot for 0425.

**The app's own toasts land in the capture.** Three shots in a row came out with

    ● zsh · a subagent finished
    ● zsh needs you — Click for details

stacked over the bottom right corner of the window, on top of the diagram. They
are not macOS notifications from another app — the capture is `cacheDisplay`
over this window's own view tree, so nothing outside it can get in. They are
this app's toasts, raised by `ClaudeHook` events from Claude Code sessions
running elsewhere on the machine, which reach whichever Abydos is running —
including a headless one taking screenshots.

So the pictures in `docs/` depend on whether somebody's agent happened to finish
in the eight seconds before the shutter, which is exactly the class of thing
that script exists to rule out. The shots for 0425 were taken by retrying until
the corner was clear, which is not a fix.

## Ruled out

Nothing has been tried yet. Two things that look like answers and are worth
thinking about before picking one:

- **Do not raise toasts on a `--screenshot` run.** The narrowest fix, and the
  run is already special-cased elsewhere — it takes the accessory activation
  policy so it cannot steal the keyboard. The question is whether "no toasts" is
  right for every headless run or only for the capture.
- **Do not draw the toast layer into the capture.** More general, and it keeps
  a capture run behaving like an ordinary one; but a toast is a real view in
  this window and something has to know to leave it out, which is a rule with an
  exception in it.

Whichever it is, a shot that *wants* a toast in it — if any ever does — has to
stay possible, since `--toasts` exists for exactly that.

**What `--toast` and `--toasts` are, since the item above has them the wrong
way round.** They are two flags, not one. `--toast` raises two of them —
"Cannot run this Go command" and "Saved 3 files" — a second after the window
opens, and that is the one a picture of a toast is taken with: `--toast
--screenshot out.png` is how the corner is looked at, and how the toasts being
unscaled at 2x was found (`ToastView.closeRect` still carries the note).
`--toasts 3,9` is a *reading*, not a picture: it prints `TOASTS: [title:
detail]` at each of those seconds, and exists because a toast cannot be told
from an empty corner in a window rendering that has not finished loading. Both
have to go on working, so "a shot that wants a toast" is not hypothetical —
it is the only way either flag is used.

**Neither of the two, and one sentence rules out both.** A capture that raises
no toasts and a capture that leaves the toast layer out come to the same thing
where it matters: `--toast --screenshot` would photograph an empty corner.
*Silently*, which is the worse half — a corner with nothing in it is exactly
what a correct picture of an app with nothing to say looks like, so the flag
would go on being used and go on proving nothing. Leaving the layer out costs
more besides: `WindowCapture.write` is what every picture in this project goes
through, and it would have had to know about one particular view class.

**What was done is narrower than either, along the axis that matters.** What
spoils a documentation shot is not that a toast is drawn — it is that *this*
toast came from outside the run: a `DistributedNotificationCenter` message
posted by an `abydos-hook` process that a Claude Code session in some other
terminal started. So a capture run does not listen for those at all
(`ClaudeWatch` never registers its observer), and everything the run itself
causes still reaches the corner and is still photographed.

**Only the capture, not every headless run** — that was the open question. A run
that is *not* taking a picture is precisely where this path would be checked:
fire the hook, then read `--toasts`. A rule about headless runs in general would
have left no way to check it at all, and that is how this was in fact measured.

**Measured through the hook, not through the toast API.** Two builds of the same
commit, one with the guard and one with it taken out, and the event raised by
running `abydos-hook` with a `SubagentStop` event on its stdin — the same binary
Claude Code runs, posting the same notification. Fired five seconds into a
nine-second capture, so the toast is still up when the shutter closes:

- **the control, without the guard:** the two pictures differ in 59,664 pixels,
  in the box `x 1688…2367, y 1480…1567` — which is the toast, and nothing else:
  340 points wide, 16 points in from the trailing and bottom edges, at 2x.
  `--toasts 7` says `[0451-proof · a subagent finished]`, and
  `images/the-toast-the-capture-caught.png` is that picture.
- **with the guard:** six runs of the shot, three of them with the hook fired,
  produced *one file*: all nine hook/quiet pairs byte-identical, and the
  reading says `TOASTS: (none)` every time.
- **and a toast still photographs:** the same build with `--toast` reports both
  demo toasts and gives a different picture again, so the corner has not gone
  blind.
- **the news is not stolen from anybody:** two capture runs listening at once
  both received the same single hook event, so a copy of the app that declines
  it costs the copy somebody is working in nothing.

**Two things found on the way, neither about toasts.**

1. *The hook marks a real tmux window.* `abydos-hook` reads `TMUX_PANE` from its
   environment and writes `@ai_status` onto whatever window that names — so a
   harness that fires it from inside somebody's tmux badges one of their
   windows. `env -u TMUX -u TMUX_PANE` is how this proof avoided doing that.
2. *A capture is not byte-stable for reasons of its own.* On the first shot
   tried — the same project with `main.go` open — six identical runs produced
   three different files. The differences are the editor caret's blink phase (a
   4×48 px bar, 192 pixels) and the overlay scroll bar under the editor, drawn
   in some runs and faded in others (a 1798×30 band). Both are outside the
   corner and neither has anything to do with this item, but they are why the
   proof above uses a shot with no file open: on that one the picture really is
   the same file every time, so "identical" means byte-identical rather than
   "identical apart from the bits that always move". Anybody diffing
   `docs/images` after this should know those two are there.

## Steps

- [x] Find out what `--toast` and `--toasts` really do, since whichever answer
      is chosen has to leave a picture of a toast possible
- [x] Decide which of the two above, and say why in the code — neither, in the
      end: what a capture declines is news from *outside* the run, which is
      the part that is not reproducible. The reason is in `ClaudeWatch`
- [x] Take the same shot twice with an agent finishing in between, and get the
      same picture — the toast raised through the hook, the way the machine
      raises it, rather than by calling the toast API
- [x] Write down here what was ruled out on the way
- [x] `spec/screenshots.md` says what the project now does
