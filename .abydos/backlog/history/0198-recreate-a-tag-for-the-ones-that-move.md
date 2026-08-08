# Recreate a tag, for the ones that move

`d2d4e3622` · 2026-08-03

`v1` pointing at the newest `v1.x` is what every GitHub Action expects, and
git will do it — as a forced tag, then a forced push of the fully-qualified
ref, because `git push origin v1` is ambiguous when a branch shares the name.
Nobody remembers that spelling, so it is a menu item on the tag itself now.

The dialog offers the newest version under the tag, sorted by version and not
by text: v1.10 beats v1.9, and sorting those as strings is how a release goes
backwards. It says where the tag is now, takes anything git can resolve, and
force-pushes by default — a moving tag that stays here moves nothing.

Four tests against real repositories, one of them pushing over a tag a bare
remote already has, which is the case git refuses without force.
