# Run and debug in a cluster from the run button

`31445afaf` · 2026-08-01

A launch configuration with `ideai.devPod` on it runs where the service
runs. Pressing run asks the cluster what its nodes are, cross-compiles
for that, forwards a port, pushes the binary and starts it; pressing
debug starts `dlv dap` in the pod instead and attaches through a second
forward. Breakpoints resolve against your own source without any path
mapping, because the binary was built here and its debug info names these
files.

The editor now asks what kind of configuration it is rather than
inferring it from a type string, and a cluster one asks where the cluster
is — context, namespace, and a kubeconfig for a cluster that lives in a
file of its own. Rows that do not apply collapse rather than hide, since
a dialog with a hole in the middle looks broken.

The chart labels the pod rather than only the Deployment: the editor
looks for pods, and it was finding none.
