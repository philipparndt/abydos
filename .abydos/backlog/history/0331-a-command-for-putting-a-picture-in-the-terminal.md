# A command for putting a picture in the terminal

`9e04675ff` · 2026-08-06

The terminal here has drawn images for a while — it speaks the kitty graphics
protocol — and nothing on a Mac ships a command that asks it to. kitty's
`icat` comes with kitty, `chafa` and `timg` draw with blocks instead, and the
one-liner with `base64` is the sort of thing nobody remembers twice.

`abydos-icat picture.png`, then. It converts anything that is not a PNG with
`sips`, chunks the payload the way the protocol asks, and wraps the escape for
tmux — with a word about `allow-passthrough` when tmux is set to eat it. It
ships inside the app and is appended to the PATH of every shell the app
starts, so it is there without an install step; `make install-cli` also puts
it in /usr/local/bin, and takes the name `icat` only when nothing else answers
to it.

Two things this turned up.

The picture came out squashed: given a width and no height, the terminal took
the image's own pixel height instead of the one the aspect ratio implies, so
`-w 20` on a square image drew twenty columns and two rows. The protocol says
the other dimension follows from the ratio, and now it does — which fixes
kitty's own `icat` and `timg` here too, not just this.

And the first version of the PATH change asked `Bundle` for its own resources
after `fork()`, where only async-signal-safe calls are legal. Foundation takes
locks; a child that inherits a held one waits for a release that never comes,
never reaches `execve`, and leaves the pane empty. The test that runs `echo`
in a pty went from passing to timing out, which is exactly the right test to
have had. The lookup happens before the fork now.
