# 406. Tool containers outlive the app, and enough of them wedge the runtime

Found on this machine on 2026-08-08: eleven `container run --rm -i
plantuml/plantuml` processes, four of them a day old, the rest from a run of
the app that had already ended. Nothing was drawing a diagram. They were simply
never stopped.

With that many of them, Apple's `container` stops answering: `container ls`
hangs, `container images inspect` hangs, and so does everything in this app
that asks a runtime a question. Every render then starts another one that hangs
too. That is what the report of "the app spams the runtime with containers"
actually was — not a loop starting them deliberately, but nothing ever ending
them. `pkill -TERM` cleared all eleven, and the runtime answered in
milliseconds again immediately afterwards.

**One cause is fixed here.** The preview's deadline used to begin `guard let
self` — so a pane closed, or a project switched, while a render was hanging
left the render running with nothing left to stop it. It now stops the process
whether or not the view is still there, and follows the polite ask with a
`SIGKILL` two seconds later.

**What is left is the bigger half:**

Three of those are now done — every tool process is registered with
`ToolProcesses` and ended when the app goes, including out of the uncaught
exception handler, which is the exit that left the eleven; renders past a cap
of twelve are refused with a sentence saying what that means; and a runtime
that misses its deadline is reported once and then answered from memory
instead of being asked again.

**What is left is the half that was only a question, and the answer is bad.**
Killing the `docker run` that started a container does not stop the container:

    docker run --rm -i --name probe alpine:3 sleep 60 &
    kill -9 $!    # container: still up
    kill -TERM $! # container: still up after ten seconds

So `--rm` never fires, and everything above ends *processes* while the
containers behind them keep running. Two of today's symptoms are unexplained
without this — a runtime service that wedges under load nobody can see, and
`container ls` hanging long after the processes were killed.

Ending a container means asking the runtime to remove it, which means knowing
which one it is. Naming it at `run` time — `--name abydos-<something stable>`
— is the readable half; the removal verb is the half to check, since docker's
`rm -f` has no confirmed spelling in Apple's CLI. It could not be checked here:
that CLI was wedged badly enough that even `container --help` never returned.

Worth doing at the same time: a name has to be free before it can be reused, so
whatever starts a container should remove a stale one of the same name first
rather than failing with "name already in use" after a crash.

---

Its number is where it sits in the queue, not what it is worth doing next.
Previously numbered 395.


## Decided

**A name, `abydos-…`, on every container we start.** The reason this was stuck
is that a container cannot be removed if it cannot be found, and an unnamed one
started by a CLI that has since been killed can only be found by guessing.

**Docker only, for now.** Apple's `container` is set aside rather than supported
half-way. Its service has been unresponsive here all day — `--version` answers,
`--help` hangs — and that is precisely the state in which a removal verb cannot
be proven to work. A feature whose whole purpose is cleaning up must be
demonstrable. The `ContainerRuntime.apple` case stays in the code so this is a
preference to revisit rather than a direction taken; what changes is which
runtime is preferred, and what is said when Apple's is the one found.

Written down because it is a reversal: `discover` preferred Apple's precisely
because it needs no daemon, and that reasoning is still sound for the day its
service is well.

## Later: the removal verb is proven, 2026-08-09

That day came. The machine was restarted and Apple's `container` answers
everything again — `--version`, `--help`, `ls`, all of it, in milliseconds.
Version 1.2.2 (build: release, commit 0190097). So the one thing this entry left
undone was done, the same way docker's was:

    container run --rm -i --name abydos-probe-outlives-apple alpine:3 sleep 300 &
    # state: running
    kill -9 $!
    # three seconds later — state: still running. `--rm` never fired.
    container rm --force abydos-probe-outlives-apple
    # gone, from `inspect` and from `ls --all` both

`ToolContainers.removal` is unchanged: `rm --force` was the right spelling. What
changed is that it is a test rather than a guess —
`ToolContainerLiveTests.killingTheProcessLeavesTheContainerAndRemovingItByNameDoesNot`
now runs for both runtimes and skips cleanly for whichever is not installed.

**The sweep works there too.** `ToolContainers.listing` returned nil for Apple's
because its table had never been seen. It does not need parsing: `container ls
--all --quiet` prints one container id per line, and for everything this app
starts the id *is* the name — `--name` is documented as "use the specified name
as the container ID". `--all` is the load-bearing flag on both runtimes, since a
crashed run mostly leaves stopped containers and neither lists those by default.
`container ls --format json` exists as well and is the fuller answer; names are
all a sweep needs, so the simpler one is used.

**Two bugs found on the way, both from the same guess.**
`ContainerImages.inspect` and `.pull` sent Apple's runtime `images inspect` and
`images pull`. There is no such subcommand — the noun is singular — and
`container` resolves an unknown subcommand as a plugin, so the answer was
`Plugin 'container-images' not found`. `isUnknownImage` matched the bare words
"not found" in that and reported it as a missing image, so somebody choosing
Apple's runtime and drawing a diagram was told *"There is no image called
plantuml/plantuml:1.2026.6. Check the name and the tag"* about a name that was
correct. It also meant the cross-runtime hint could never be reached. **Nothing
image-backed had ever worked on Apple's runtime**, and the failure blamed the
user. Both are fixed, and `ContainerImageLiveTests` now asks the real CLI
whether the commands this app sends are ones it has, which is the check that
would have caught it the day it was written.

**What is still refused, and it is not cleanup.** Nothing here can reach one of
Apple's containers over the network. A published port is listened on and every
connection to it is accepted and reset, because the runtime's own forwarder
cannot connect to the container behind it — `No route to host` in its log. A
container's own address on `bridge100` is the same from this side: `connect(2)`
from a freshly built binary returns `EHOSTUNREACH` while `curl` from an approved
terminal fetches a picture from that exact address in the same second. That is
macOS's local-network privacy, and the runtime's helper is subject to it as much
as this app is. It is not this app's containers only — the machine's own
`mycluster` fails the same way on the port it published.

So `discover` still prefers docker, and the reason recorded in `ContainerRuntime`
has been rewritten to be that one rather than cleanup. Everything else is proven
on Apple's runtime: removal, the sweep, the image pull, bind mounts, `-d` with a
keep-alive, `--entrypoint`, `-u`, `-e`, `-w`, and `exec -it` onto a real pty.
Allowing local network access to `container` in Privacy & Security is the thing
to try, and if it works, one line moves.
