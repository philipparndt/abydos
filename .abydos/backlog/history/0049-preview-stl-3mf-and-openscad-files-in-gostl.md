# Preview STL, 3MF and OpenSCAD files in GoSTL

`199387ece` · 2026-07-31

A "Preview in GoSTL" action on the navigator's context menu and on the
notice shown for a binary file, since STL and 3MF land there today.

Launched rather than embedded. GoSTL's package vends an executable
product, and an executable target cannot also be linked into another
app, so there is nothing to depend on yet. Launching costs nothing and
gives most of what embedding would: GoSTL watches the file it is given,
so editing a .scad here refreshes the preview there without ideai doing
anything at all.

The action is hidden rather than shown-and-broken when GoSTL is not
installed, and the executable is looked for in the Homebrew locations
directly — a GUI app does not inherit a login shell's PATH.
