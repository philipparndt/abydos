# Stop the editor crashing when split with a model open

`f3cb2f534` · 2026-07-31

NSHostingView publishes the SwiftUI view's size as constraints and
invalidates them from inside the window's own constraint pass. Splitting
the editor re-parents the view during exactly that pass, and AppKit raises
rather than re-entering it — so Window > Split Right with a model tab open
took the app down. The preview is now kept out of Auto Layout entirely and
sized by its container, which is how the rest of the editor lays out anyway.

While it is there, the viewer is told it is embedded: it takes the editor's
background so the split reads as one surface rather than two applications,
and keeps its menu panel folded away, since that panel is wider than the
pane often is.
