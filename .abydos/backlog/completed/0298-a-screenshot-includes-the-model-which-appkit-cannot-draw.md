# A screenshot includes the model, which AppKit cannot draw

`95dc89b60` · 2026-08-05

A window is captured by walking its view tree — `cacheDisplay(in:to:)` — and a
`CAMetalLayer`'s contents are not in it. So a `.scad` open beside its source
photographed as an empty rectangle: the viewer's SwiftUI chrome appeared, and
the model it exists to show did not.

A view that holds such content now says so, and the capture asks it for a
picture afterwards and draws it where that view is. GoSTL renders the same
scene into a texture for the purpose — the pass matches the view's, 4×
multisampled bgra8Unorm resolved into a readable texture with depth32Float, so
what is published is what was on screen rather than a second-best of it.

The same seam works for anything else that draws through Metal and cannot be
photographed: conform, answer with an image.
