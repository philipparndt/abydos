# A pod that waits for a binary

`6337353a1` · 2026-08-01

The loop this replaces is the one every microservice team knows: build an
image, push it, upgrade a release, wait for a pull — minutes, and again
for every one-line change. Pushing a freshly built binary into a pod that
is already running took 0.05s on a real cluster here; with the build,
0.2s from edit to running.

The pod is the real workload in every way but one. It gets the chart's
config, secrets, service account and sidecars; only what runs inside it
comes from the editor. It starts empty, which is a healthy state and not
a failure — that is what lets it exist before the first push and survive
a program that crashes on startup, since a crash loop would otherwise
take the pod away mid-session.

The supervisor answers the probes itself, for the same reason: a
breakpoint is not a reason to restart a pod. `mode=debug` starts `dlv
dap` instead of the program, so the editor attaches over a port-forward
and decides what to launch.

The image is assembled without a builder — two static binaries, a tar, a
config, a manifest — because requiring Docker means requiring Docker to
work, and behind a corporate proxy that is exactly what often does not.
The output is a docker-save tarball, which containerd, k3d, k3s's
auto-import directory and `docker load` all accept.

Also: the run strip is now as wide as what it says, so with nothing to
report it has the same margin at both ends; and choosing another project
switches this window rather than opening a second one, with a setting for
those who want the opposite.
