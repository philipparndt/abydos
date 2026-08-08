# Save what the gutter would run, and prove what was pushed

`695fd5d98` · 2026-08-02

The arrow beside `func main` already knows the package, the arguments and
where it runs, which is a launch configuration with no name on it. It can
now be saved as one — opened in the editor first, so the arguments can be
filled in before the first run — and a name already taken gets a number
rather than replacing what somebody else wrote in a shared file.

The dev pod's log tail is also cleared when a binary is pushed. Kept, it
showed the previous program's output beside the new one's with no way to
tell them apart — which is exactly what "it did not refresh" looks like.
The status line now says how much was sent and how much the pod is
running, since a program that looks unchanged is the first thing to
doubt.
