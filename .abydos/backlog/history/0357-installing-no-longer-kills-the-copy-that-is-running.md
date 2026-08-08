# Installing no longer kills the copy that is running

`01b7d20d9` · 2026-08-07

`rm -rf /Applications/Abydos.app` followed by `cp -R` is the obvious way
and it is the wrong one. A running application has its executable and
its resources mapped out of that bundle, and macOS checks every page
against the signature as it is faulted in; copy a different build over
the same paths and the next page no longer matches what it was signed
with. The kernel kills it minutes later with CODESIGNING / Invalid Page
and nothing points back at the install that caused it. Three of today's
crash reports are that, and both times the installing was done by
another session while the app was open.

It installs beside the old bundle and swaps by rename now. A rename
unlinks rather than overwrites, and an unlinked bundle stays whole for
whoever still has it open, so the running copy keeps the build it
started with until it is quit — and is told that it should be.

`ditto` rather than `cp -R`, since the signature lives in extended
attributes that `cp` does not always carry.
