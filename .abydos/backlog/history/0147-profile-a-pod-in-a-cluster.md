# Profile a pod in a cluster

`4e6dda212` · 2026-08-01

Pick it from the pod list and a port-forward is opened to it, so a
workload in Kubernetes profiles exactly like a local program. Through
kubectl, which already knows the kubeconfig, the contexts, the exec
plugin the cluster authenticates with and the proxy in front of it —
every one of those a project on its own, and all of them already solved
by the tool on the PATH.

The port is the part that goes wrong, so the list says where each pod's
pprof is and how that was decided: annotated, declared, or a guess.

The flame graph also grows upwards from the root now, the way one is
read, and opens anchored on it — a recursive program was showing the
narrow tip of itself and nothing that explained it.
