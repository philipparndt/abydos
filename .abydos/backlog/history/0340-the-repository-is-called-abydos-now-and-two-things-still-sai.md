# The repository is called abydos now, and two things still said otherwise

`d1080b9e7` · 2026-08-07

The remote moved, so the releases link in the README follows it. GitHub
redirects the old address, which is exactly why a stale link survives
unnoticed until the redirect is the only thing holding it up.

And `make dev` and `make shot` ran `Contents/MacOS/ideai`, a path that
stopped existing when the app was renamed — the bundle has held `Abydos`
since then, and both goals had been failing on a missing file.

The bundle identifier is untouched, and stays untouched: the Local Network
grant is keyed to it, and renaming it is what cost a day.
