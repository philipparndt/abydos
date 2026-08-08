# A folder that stops being ignored stops being grey

`43059d3f0` · 2026-08-08

Adding `!backlog/` to an ignore file and saving it left the folders it
un-ignored drawn as ignored, for the life of the project. Two independent
faults, and either one alone was enough to produce exactly that.

The status was only re-read when a directory somebody had *expanded* was
re-read with it. An edit to an ignore file changes the status of files that
did not themselves change — that is the whole point of an ignore file — so
whether the colours caught up depended on which parts of the tree happened
to be open. The navigator now asks on every filesystem change, which it can
afford because the read coalesces: one `git status` at a time, with at most
one queued behind it.

And re-reading would not have helped, because the directory statuses were
never replaced. The line dropping the memoised rollups also kept every
explicit `ignored` entry it had ever seen, so a folder that had once been
ignored answered ignored for ever. They are now built fresh from the porcelain
beside the file statuses, which is what the files always did.

The test parses two listings into one repository — before the rule was
changed and after — and asserts the folder comes back. It fails against
either half of the old behaviour.

Two paths named in the backlog entry are still not covered, and cannot be by
this: `.git/info/exclude` lives inside a directory the tree does not watch,
and a global ignore file is outside the project altogether. Both still need
something else to happen before the colours catch up.
