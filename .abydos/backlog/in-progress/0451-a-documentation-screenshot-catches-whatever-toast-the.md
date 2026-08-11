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

## Estimate

2026-08-11 12:41 — about ninety minutes left

## Steps

- [x] Find out what `--toast` and `--toasts` really do, since whichever answer
      is chosen has to leave a picture of a toast possible
- [ ] Decide which of the two above, and say why in the code
- [ ] Take the same shot twice with an agent finishing in between, and get the
      same picture — the toast raised through the hook, the way the machine
      raises it, rather than by calling the toast API
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
