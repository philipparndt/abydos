# A remote to push to, and something to look at while it pushes

`601be772a` · 2026-08-03

Setting a remote from the branches list: a repository made with `git init` has
none, and everything that talks to one — pushing, opening the branch on
GitHub — has nothing to say until it does. One menu item covers both cases,
because "no remote" and "pointed at the wrong place" are the same problem to
whoever is looking at it; `add` versus `set-url` is git's distinction, not
theirs.

And a spinner on the branch while it is being pushed. A push talks to another
machine and can sit there for seconds on a slow link, and a list that looks
exactly as it did is indistinguishable from a click that never landed. The
ahead/behind counts give it room rather than sitting under it.

Also: opening a sidebar that had been dragged shut now gives it a width. It
was opened to whatever it had been left at, which for a sidebar dragged shut
is nothing at all — so it "opened" and stayed invisible.
