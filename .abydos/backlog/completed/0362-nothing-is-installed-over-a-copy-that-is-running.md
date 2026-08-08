# Nothing is installed over a copy that is running

`e9b19aa88` · 2026-08-07

The swap put in the last commit keeps a running app's own bundle intact,
and that is still not enough. The old bundle is deleted afterwards, and an
application that has not yet loaded every nib, framework and resource it
is going to load needs the files it started with to still be there. There
is no way to know when it is finished with them, and a program that
quietly loses half its bundle fails later and somewhere else — which is
what "it crashed during make install and there is no crash report" looks
like, and there were no reports.

Quitting first is needed to get the new build in any case, so this asks
for it rather than working around it. FORCE=1 for somebody who means it,
and even then the retired bundle is kept rather than deleted for as long
as something is running from it.

Staging moved out of /Applications too. A second bundle appearing there
with the same identifier is a second registration, however briefly, and
LaunchServices is entitled to decide what that means for the copy already
running. TMPDIR is on the same volume, so the swap is still a rename.
