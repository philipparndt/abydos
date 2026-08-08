# Two captures that said they were being careful and were not

`540cb13df` · 2026-08-04

`[weak self]` inside a scope that already holds a strong `self` is not a
weak capture of anything: the outer one keeps the object alive for the
whole time, and the inner one only looks like it is guarding against that.
Swift 6.4 says so, and it is right.

Weak from the top in both — the repository watcher's lookup, and the tag
dialog, which is modal and can outlive the pane that raised it.

These were not new. The sweep that reported this build warning-free
matched "warning:" followed by a path, and the compiler prints the path
first, so it could never have found them.
