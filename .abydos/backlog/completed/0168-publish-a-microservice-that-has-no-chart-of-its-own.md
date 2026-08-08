# Publish a microservice that has no chart of its own

`46781c9e1` · 2026-08-02

A service is tested by talking to it, and a pod in a cluster is not somewhere
a browser can reach. A dev pod configuration can now say a hostname and the
port the program listens on: the chart publishes it through whichever of
Gateway API, Traefik or a plain Ingress the cluster has, and a forward to the
pod's port is opened either way — so "it is running" comes with a link even
on a cluster with no DNS for it.

A running pod is not necessarily a pod set up the way the configuration now
asks for. What the release was installed with is compared against what is
wanted, and the chart is upgraded when they have drifted apart — otherwise a
configuration that gained an ingress would be ignored until somebody deleted
the release by hand.

Also: the torn-off terminal window no longer draws the panel's own controls.
There is no panel to hide or maximise out there, and following the shell's
project belongs to the window that has a project in it.

Verified against k3c-demo1: an Ingress for makeproj.dev.local, and the
service answering "makeproj is alive" with the config file it was sent.
