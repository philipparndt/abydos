# Fill the window when told to, every time

`90b08eae7` · 2026-08-03

Two reasons it did not.

Maximising divides the window's height, and a window that has not been laid
out has none to divide — the split quietly does nothing and the terminal
stays where it was. It waits for a height now, checking each turn of the
runloop and giving up after a second rather than spinning.

And it deferred to what the project was last left with: a project whose
session said the panel was closed never opened one, however the setting was
set. The setting is explicit and wins — somebody who asked for the terminal
to fill the window asked for every window, not for the ones whose session
happens to agree.

Three fresh projects in a row now open with the terminal filling the window.
