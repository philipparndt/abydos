# Keep the tab bar clear of the titlebar across a zoom change

`a228ae0c2` · 2026-07-31

Zooming in and back out left the tab bar tucked under the titlebar, looking
as though the tabs had stopped being drawn.

A pane gets the titlebar inset only when the titlebar is what is above it,
and that was decided by comparing the pane's frame with the split host's
bounds. A zoom change resizes the tool strip, so everything to its right
resizes too, and the check ran again mid-pass with the pane still holding
its old height against a host that already had the new one — 793 against
789. Close enough to look like a pane that does not reach the top, so the
inset went to zero, and no later pass put it back.

It is read from the split tree now: only a stacked split puts one pane
below another, so a pane touches the top unless some split above it has it
as the lower half. No frames, nothing to be mid-update.

Found with --zoom-cycle, which zooms in and out once the window is up;
setting the zoom at launch, as --zoom does, never exercises this.
