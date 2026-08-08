# Give the terminal its own colours, and make dim actually dim

`f1ebd2ae8` · 2026-08-01

Two schemes, chosen under Settings. Blue is the palette Ghostty ships with,
on the background from this machine's ghostty config, and is the default;
Dark is what the terminal had, which matches the editor's own colours.

Its own setting rather than the editor's theme: a terminal's palette is a
language of its own — prompts, diffs and full-screen tools all mean something
by it — and people arrive with one they already know.

Faint text was left at sixty per cent of its colour, which against a dark
background is barely distinguishable from ordinary text: the greyed-out
status line a full-screen tool draws came out as bright as the rest. It is
0.45 now, blended towards what is behind it rather than towards black, so it
stays faint against any background. One constant, used by both renderers.

The palette rebuilds when the scheme changes rather than being looked up per
cell, since a screen repaint asks for two colours for every cell on it.

Settings grew a picker to choose with; it only had toggles, sliders, steppers
and text before.
