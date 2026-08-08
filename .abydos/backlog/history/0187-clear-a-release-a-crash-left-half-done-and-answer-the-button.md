# Clear a release a crash left half-done, and answer the button at once

`ae5d39d72` · 2026-08-02

helm refuses every attempt after an operation that never finished — "another
operation (install/upgrade/rollback) is in progress" — and stays that way
until somebody clears it by hand. For this app's own chart in a development
cluster there is nothing worth keeping, so it is cleared and the install
tried again: a pending install is removed, a pending upgrade rolled back to
what worked. A project's own chart is not touched — it says what to run
instead, since removing a release somebody else owns is not this app's
decision.

Verified against a genuinely stuck release: helm killed mid-install left
ideai-stuckproj pending-install and refusing upgrades; pressing run cleared
it, installed, and left a pod running.

And the buttons answer immediately. Starting means building and stopping in a
cluster means asking a pod across a network, so the titlebar takes its colour
the moment run is pressed and drops it the moment stop is — while the button
goes on saying "stop" until the program has actually stopped. A second press
of stop is ignored rather than queued, which is what made it look like the
first one had missed.
