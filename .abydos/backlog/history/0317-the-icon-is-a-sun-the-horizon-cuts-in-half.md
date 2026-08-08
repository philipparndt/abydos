# The icon is a sun the horizon cuts in half

`a8b591f81` · 2026-08-06

A half-circle on a flat line is geometry that can be redrawn from memory,
and it is still legible at sixteen points where a landscape would not be.
The sky is kept near-black on purpose: macOS derives a tinted, single-hue
variant of every icon, and that transform keeps luminance and discards
colour, so a sunset carried by its gradient would arrive as grey bands.

Two numbers are load-bearing. The horizon sits at five eighths of the
icon's height, which puts it on a whole pixel at every size macOS asks for
instead of smearing it across two. The sun's gradient spans only the half
above the line, because running it across the whole disc spends the amber
end below the ground, where nothing can see it, and leaves the visible
half pale.

The script now writes the asset catalog as well as the .icns. It only ever
wrote the latter, so an Xcode build and Scripts/bundle.sh disagreed about
what the app looked like, and the catalog had been carrying whatever was
last copied into it by hand.
