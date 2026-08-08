# A presentation mode, with its own zoom and its own palette

`ed4291277` · 2026-08-04

View ▸ Presentation Mode. Bigger, because the size a room needs is not the
size a desk does, and light by default, because a projector turns a dark
theme into a grey smear.

A second pair of preferences held alongside the first rather than a mode
that saves the working pair somewhere and puts them back: everything that
draws asks for whichever is in force, so there is nothing to restore and
nothing that can leave a talk's zoom behind after the talk. ⌘+ in the middle
of a demo makes the demo bigger and leaves the desk exactly as it was.

The light palette had a bug waiting for this: a selected file's name was
near-white, which was written for the dark theme's blue pill and disappeared
entirely on the light theme's pale one. It takes its ink from the palette
now.

`--presentation` shows the window this way for a screenshot without storing
the mode — the harness shares a preferences domain with the installed app,
and a test must not leave somebody's editor presenting to an empty room.
