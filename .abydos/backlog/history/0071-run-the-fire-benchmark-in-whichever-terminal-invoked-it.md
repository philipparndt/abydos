# Run the fire benchmark in whichever terminal invoked it

`99f73696a` · 2026-08-01

    make fire
    SECONDS=60 make fire

It ran inside the app's own terminal before, through the screenshot harness,
which gave one figure for one small pane. The point of this benchmark is
comparing terminals, so it now simply burns in whatever terminal you ran it
from — ours, Ghostty, Terminal.app — at whatever size that window happens to
be. Same command everywhere, and the size it measured is in the result line.
