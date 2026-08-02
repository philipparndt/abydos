# The development pod

A pod that waits for a binary, runs it, and lets a debugger in.

The loop it replaces is the one every microservice team knows: build an image,
push it to a registry, upgrade a release, wait for a pull. That takes minutes.
Building a Go binary and pushing it into a pod that is already running takes
about a second — measured, on a k3s cluster, below.

Nothing about the pod differs from the real workload except what runs inside
it. It gets the chart's ConfigMaps, its Secrets, its service account, its
sidecars, its network identity. The program under development runs where the
program normally runs.

## The pieces

- `supervisor/` — PID 1 in the pod. Receives a binary over HTTP, writes it
  atomically, runs it, and answers the probes itself so a breakpoint never
  costs you the pod.
- `chart/ideai-devpod/` — a Helm chart that runs one.
- `tools/mkimage/` — assembles the image without a Docker daemon.
- `Dockerfile` — the same image for a registry, when you have a builder.

## Building the image

```sh
make image ARCH=arm64          # or amd64 — match the cluster's nodes
make import-k3c CLUSTER=demo1  # local k3c
make import-k3d CLUSTER=dev    # local or remote k3d
```

`make image` needs no Docker: it cross-compiles the supervisor and Delve and
writes a docker-save tarball, which is what containerd, `k3d image import`,
`docker load` and k3s's auto-import directory all accept. Behind a corporate
proxy that is one fewer thing that has to be working.

For a shared cluster, build `Dockerfile` instead and push it somewhere the
cluster can pull from.

## Publishing the image

A remote cluster cannot be handed a tarball — it pulls — so for anything but a
local cluster the image has to be in a registry:

```sh
make publish                                # pharndt/ideai-devpod:dev
make publish VERSION=v1 PLATFORMS="amd64 arm64"
```

Both architectures in one image, and still no Docker: everything inside is a
static binary, so each architecture is one layer of two files and publishing is
a handful of blob uploads and an index. `mkimage -push` speaks the registry
protocol itself. It logs in with what `docker login` left in the keychain, or
with `DOCKER_USERNAME` and `DOCKER_PASSWORD`.

That published image is what the chart runs by default, so a cluster with a
network needs nothing else. A local cluster given the same reference by
`make import-k3c` or `make import-k3d` keeps its own copy — `IfNotPresent`
means what is already there wins, which is what makes working on the
supervisor itself possible.

A configuration can name a different one in its Image field, or:

```sh
--set image.repository=pharndt/ideai-devpod --set image.tag=v1
```

## Installing

```sh
helm upgrade --install dev chart/ideai-devpod -n devpod --create-namespace \
  --set image.pullPolicy=Never \
  --values my-service-dev.yaml
```

Point `app.envFrom` at the real ConfigMaps and Secrets, `app.ports` at the
ports the service serves, and `podLabels` at the real workload's selector
labels if you want its Service to route here.

## From the editor

A launch configuration with one extra key runs in the cluster instead of here:

```json
{
  "name": "in the cluster",
  "type": "go",
  "request": "launch",
  "program": "${workspaceFolder}/app",
  "args": ["/etc/config.json"],
  "ideai.devPod": { "context": "k3c-demo1", "namespace": "devpod" }
}
```

Press run and ideai asks the cluster what its nodes are, cross-compiles for
that, opens a port-forward, pushes the binary and starts it — the pod's output
arrives in a panel tab. Press debug and the pod starts `dlv dap` instead; the
editor attaches through a second forward and stops on your breakpoints, in
your source, because the binary was compiled here and its debug info names
these files.

The configuration editor has a **Type** at the top — Go package, executable,
or dev pod — and a dev pod configuration also asks for the cluster, the
namespace and a kubeconfig when it is not the default one.

## Using it

The pod starts empty — that is a healthy state, not a failure.

```sh
kubectl port-forward deploy/dev-ideai-devpod 7999
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -gcflags 'all=-N -l' -o /tmp/svc .
curl --data-binary @/tmp/svc 'http://localhost:7999/binary?mode=run'
```

`mode=debug` starts `dlv dap` instead; forward 2345 and attach a DAP client,
which is what ideai's debugger does.

| endpoint | what it does |
|---|---|
| `GET /healthz` | always 200 — the probes point here |
| `GET /status` | state, pid, exit code, binary size and time, arch |
| `POST /binary?mode=run\|debug&start=true` | receive, replace, restart |
| `POST /start?mode=…`, `POST /stop` | without pushing |
| `GET /logs?tail=N` | the program's recent output |

Bodies may be gzipped (`Content-Encoding: gzip`) — worth it over anything
slower than a LAN, and not worth it on the same machine.

## Publishing it

Off by default — a development pod that puts itself on a hostname by accident
is worse than one you have to ask. Turned on, the kind of object is worked out
from what the cluster has:

```sh
helm upgrade --install dev chart/ideai-devpod -n devpod \
  --set ingress.enabled=true --set ingress.host=my-service.dev.example.com
```

| the cluster has | what you get |
|---|---|
| Gateway API, and `ingress.gateway.name` set | `HTTPRoute` |
| Traefik's CRDs | `IngressRoute`, with entrypoints and middlewares |
| neither | `Ingress`, which every controller understands |

A Gateway API route without a parent gateway routes nothing, which is why
naming one is what selects it. `ingress.mode` forces any of `gateway`,
`traefik`, `ingress` when the guess is wrong.

If the point is to take over an existing hostname rather than add one, leave
this off and set `podLabels` to the real workload's selector labels: its
Service — and therefore whatever already routes to it — sends traffic here.

## A project with a chart of its own

A real project usually has one: values files per stage, secrets through
`helm-secrets`, an application and a web front end in one pod, a cache beside
them. Reproducing that with the chart above would reproduce it badly — and the
parts that would drift are exactly the parts that matter, like what the
containers are given and what they can reach.

So the project's chart is installed as it is, and then one container of it is
swapped for the supervisor:

```json
{
  "name": "app in the cluster",
  "type": "go",
  "program": "${workspaceFolder}/app",
  "ideai.devPod": { "context": "${currentContext}", "namespace": "dev" },
  "ideai.helm": {
    "chart": "deploy/chart",
    "release": "smarthome",
    "values": ["deploy/values-dev.yaml"],
    "secrets": true,
    "container": "app"
  }
}
```

Same pod, same environment, same mounted secrets, same neighbours — with the
binary from this machine running in it. A pod with two containers in it is two
configurations, one naming `app` and one naming `web`, and each replaces its
own; the other goes on running what the chart says.

The patch is a strategic merge, so it merges into the container of that name
rather than replacing the list. It takes the probes off — they test an
application that has not arrived yet — and labels the pod the way the
development pod chart labels its own, so one way of finding a pod finds both
kinds. `kubectl rollout undo` puts the real container back, and so does running
the chart again.

## Speed, measured

On this machine against a local k3s cluster, for a small Go service:

| step | time |
|---|---|
| incremental cross-build with debug symbols | 0.15 s |
| push into the pod and restart | 0.05 s |
| **edit to running in the cluster** | **~0.2 s** |

The binary was 2.2 MB. A 12 MB service gzips to 6 MB in 0.16 s and streams to
a pod at roughly 60 MB/s, so the loop stays near a second for a real service.

## The rules the binary must follow

- Built for the node's architecture. `kubectl get node -o jsonpath='{.items[0].status.nodeInfo.architecture}'`.
- Statically linked — `CGO_ENABLED=0` for Go, a musl target for Rust — because
  the image is a scratch image with no libc in it.
- Symbols kept if you mean to debug it: no `-ldflags "-s -w"`, and
  `-gcflags 'all=-N -l'` so the optimiser stops moving your variables.
- Delve in the image must be new enough for the Go that built the binary.
  `DELVE=v1.26.2 make image` pins it.

## Other languages

The transport carries a file and restarts a process, so anything that compiles
to a static binary works the same way. Only the debugger differs: Rust, Zig,
C and C++ want `lldb-server` or `gdbserver` in the image rather than Delve, and
JVM, Node and Python want no cross-compilation at all — copy the sources and
attach over JDWP, the inspector, or debugpy.
