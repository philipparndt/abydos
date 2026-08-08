# Keep a project's own folder beside it

`80a8d6619` · 2026-08-02

Launch configurations move into `.ideai/run`, one file each, so two
people adding one on the same afternoon do not meet in a merge conflict —
and a `.gitignore` in the folder commits those and ignores everything
else, because what was open on one machine is nobody else's business.
A `.vscode/launch.json` is imported once and then left alone rather than
taken over.

What was open is written on every tab change, not at quit, so a window
that never says goodbye still comes back to the same files. Switching
project in a window now restores that project's editors from the folder
rather than only from this run's memory.

Also: configurations can be duplicated, since one local and one in a
cluster differ by two fields; a test run never becomes a saved
configuration, or a project would collect one per test function; File ▸
New Window opens a second window on the same project; and a cluster with
no development pod gets one installed rather than an error.

The run message moved to the middle of the titlebar with a cross to
dismiss it, so a message that grows no longer moves the buttons — and
every titlebar item now carries a menu form, so a window too narrow to
draw them puts them in the overflow menu instead of dropping them
silently. The run strip is the last to go.
