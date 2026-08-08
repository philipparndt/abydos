# Installing no longer asks to be forced

`344198fad` · 2026-08-08

The refusal was added on the theory that installing over a running copy
was what kept killing the app. It was not: the app was dying of SIGPIPE,
fixed in a78c737, and refusing to install was a toll charged for a
crossing that was never the problem.

What actually protects the running copy stays: the swap is a rename, so
the old bundle is unlinked rather than overwritten and whatever is
running keeps every file it started with, and the retired bundle is kept
rather than deleted while something is still running from it. It still
says that the running copy is running the old build.
