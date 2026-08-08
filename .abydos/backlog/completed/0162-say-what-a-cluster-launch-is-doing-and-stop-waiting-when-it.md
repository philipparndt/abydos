# Say what a cluster launch is doing, and stop waiting when it is hopeless

`a57f2cbb3` · 2026-08-02

`helm --wait` says nothing for two minutes and then reports its own
deadline — "context deadline exceeded" — while the cluster has been saying
since the fourth second that it cannot pull the image. So the install is now
watched: pod states go into a launch log as they change, and a pod in a
state a cluster does not recover from ends the attempt at once, with the two
ways out written down (import the image locally, or publish one and name it).

The whole launch reports itself the same way — context, pod, architecture,
each file sent, the push, the attach — because a spinner and one line of
status cannot tell a slow step from a stuck one. And the stop button now has
something to stop: the launch is a task that is cancelled, and helm is
terminated with it.

The strip keeps one line of it. A message with newlines used to draw a
paragraph across the titlebar; the rest is in the tooltip, the toast and the
log.

The chart runs the published image by default now that there is one:
pharndt/ideai-devpod:dev, both architectures. A local cluster handed the
same reference by `make import-k3c` keeps its own copy, which is what makes
working on the supervisor itself possible. A configuration can name another
image — a cluster that has to pull needs to be told what.

The app ships a copy of the chart, and a copy drifts: a test now fails when
the two differ, and `make build` syncs them. That drift is exactly why the
pod kept running the old image name.

Verified against k3c-demo1: uninstalled, relaunched, pulled
pharndt/ideai-devpod:dev from Docker Hub, sent the config file, ran. And
with a deliberately unpullable image, the attempt ends in about four seconds
with the explanation instead of hanging for two minutes.
