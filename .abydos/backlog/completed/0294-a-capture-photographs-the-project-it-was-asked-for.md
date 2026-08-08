# A capture photographs the project it was asked for

`62b473f02` · 2026-08-05

Screenshots of the wrong project, silently, for an afternoon. `--open` was
parsed, the project was opened, its session was written — and by the time the
shutter came the window was showing a different checkout entirely.

The terminal was doing it. A restored tmux session's shell sits wherever it was
left, "follow the terminal" is on, and following means switching the window to
whatever project that directory belongs to. Which is right when somebody is
working and wrong when a screenshot was asked for by name, so a capture run no
longer follows.

Two flags with it, both for the same reason — a picture for the documentation
has to look the same on two machines, and the window frame and the split
position are remembered per machine:

  --window-size 1600x1000   the whole window, centred
  --panel-height 240        the bottom panel, or 0 to close it

And the capture says what it photographed, because the failure it hides is one
nobody would otherwise notice until the picture was already published.
