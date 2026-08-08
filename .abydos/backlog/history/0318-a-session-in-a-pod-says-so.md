# A session in a pod says so

`2e5992446` · 2026-08-06

Debugging in a cluster looks exactly like debugging here: the same toolbar,
the same stack, the same variables. That is the point of it, and it is also
how somebody comes to read a stack from a pod believing it is their laptop —
and step through it wondering why the file on screen does not match.

So a session knows where it runs, and the toolbar wears it: a chip beside the
state reading `devpod/mqtt-lamarzocco-7d9f`, which is the namespace and the
pod, in the form `kubectl` would want to be told to find it again. Nil means
here, and here needs no saying.

Left out rather than clipped when the toolbar is narrow: a pod name cut in
half is worse than no tag. `--toolbar-image` draws the bar on its own, since a
session in a cluster cannot be conjured in a capture run and the tag is the
one thing that differs.
