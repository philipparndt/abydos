# Pick the pod image from the language, and keep the tree honest

`689cb0d4c` · 2026-08-02

Two things, both about not making somebody say what is already known.

The image: a pod carries a debugger, and a pod only ever debugs one
language, so there is no reason to ship both. What the project is written in
already decides how it is built, and now it decides what it runs in —
:dev-go for Go, :dev-native for Zig, Odin, C, C++ and Rust, and the full
:dev when nothing was recognised, since that one has both and a make step
builds whatever it likes. Verified in k3c-demo1: the Zig example pulled the
13 MB image and the Go example the 27 MB one, neither configuration naming
an image at all.

Anything typed into the field still wins. A cluster that mirrors one tag is
not something to be clever about.

While wiring it up: the chart writes `{{ repository }}:{{ tag }}`, and a
reference with a tag in it was being set as the whole repository — so
`pharndt/ideai-devpod:v2` became `...:v2:dev`, which exists nowhere. It is
split now, and a registry with a port in it is not mistaken for a tag.

The tree: arrow keys moved the highlight and showed nothing, which reads as
a broken navigator — you press down and the editor sits there. Moving the
selection now opens the file provisionally, exactly as a click does, with
the keyboard staying in the tree so the next arrow works. Return still pins
the tab and moves focus.

And the two things a tree this size cannot do for itself, in the header and
in the context menu: collapse all, and find the file the editor is showing.
Collapsing keeps the selection by moving it to the folder it went into,
because losing it sends the next arrow key back to the top.

--tree drives all of it from the command line and prints what the tree and
the editor each did, which is how the above was checked rather than argued.
