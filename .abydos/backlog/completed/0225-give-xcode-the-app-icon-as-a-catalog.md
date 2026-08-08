# Give Xcode the app icon as a catalog

`5ad9407b9` · 2026-08-03

The .icns alone is enough for the bundle the Makefile assembles by hand,
but not for Xcode's target editor or for App Store Connect: both want a
compiled asset catalog. The catalog is built from the same PNGs the
.icns is, so the two cannot show different pictures.
