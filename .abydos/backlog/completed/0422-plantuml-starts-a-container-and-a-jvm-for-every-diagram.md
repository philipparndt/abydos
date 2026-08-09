# 422. PlantUML starts a container and a JVM for every diagram

Every render is `docker run --rm -i plantuml/plantuml -pipe`, so a preview that
refreshes as somebody types starts a container and a JVM each time. Measured on
this machine, with the image already pulled:

| | per render |
| --- | --- |
| `docker run --rm` per diagram | **2.0 s** |
| container start alone, `-version`, no diagram | 0.7 – 1.0 s |
| warm `--http-server`, same diagram | **0.05 s** |

Forty to one, and the same picture: 1595 bytes both ways, byte for byte. Of the
two seconds, roughly 0.8 is the container and 1.2 is the JVM and PlantUML
starting. Keeping one alive removes both.

The first request to a freshly started server costs 0.53 s and every one after
it costs 0.05 — that is the JIT warming, and it is worth knowing because it
means the *second* diagram is where the win appears, not the first.

## What the image already offers

`--http-server[:<port>]` — the current image's own flag, listed in its `-h`.
There is no `-pipedelimitor` in this version's help, so feeding several
diagrams through one `-pipe` session is not the route.

The endpoint wants the source encoded in the URL. PlantUML's own compressed
encoding is not needed: `~h` followed by the hex of the plain source works, and
was how the 0.05 s above was measured —

    GET /plantuml/png/~h<hex of the .puml text>

## Decided

**Containers are named `abydos-…`.** So a kept one can be found again, and so
anything left behind is obviously ours and obviously safe to remove.

**Docker only, for now.** Apple's `container` is set aside for these two items
rather than supported half-way — it has been wedged on this machine all day,
which is exactly the state in which a removal verb cannot be proven, and a
feature that keeps a container alive must be able to prove it can kill one.
This is a decision to revisit, not a direction: the `ContainerRuntime.apple`
case stays, and what changes is which runtime is preferred and what happens
when Apple's is the one found.

## What has to be decided before this is built

**Naming and reaping the container.** This makes 0406 — tool containers
outliving the app — materially worse rather than incidentally: today's
containers are `--rm` and die with the render, and a kept one is a container
that must be found and stopped. It needs `--name` so it can be found again, and
0406's removal verb, which is still unproven while Apple's `container` service
is wedged. **These two should probably be done together, and 0406 first.**

**An idle timeout.** Otherwise every project somebody opens leaves a JVM
resident for the rest of the day. A few minutes after the last render is
probably right; the cost of getting it wrong is one 2-second render, which is
exactly what happens now.

**How long a URL may be.** The `~h` form carries the whole diagram in the
request line. Fine for a preview pane, and worth checking against the largest
diagram in the examples repository before relying on it — if it is a problem,
PlantUML's compressed encoding is the answer and is more work.

**Which runtime.** Apple's `container` gives each container its own light VM,
so its start cost is higher than docker's 0.7 s and the case for keeping one
warm is stronger there, not weaker. Worth measuring both before choosing a
number for the idle timeout.

**What happens when it is not there.** A server that has died, a port already
taken, a runtime that has stopped answering: the answer should be to render the
old way rather than to fail, since the old way works and is only slow.
`ContainerImageStore` already has the shape of this — one report and then a
fast no.

## Worth saying out loud

The same argument applies to the language servers, and it already went the
other way there: those are long-lived by nature, one per project, and they are
started once. PlantUML is the odd one out because a preview re-renders on every
keystroke and the tool it uses was built as a command-line program.

## Later: still docker only, for a different reason, 2026-08-09

Apple's `container` answers again (1.2.2), and the reason written above no
longer holds: **`container rm --force` is proven end to end** — see 0406's own
later note. A kept container there can be killed again, so the objection that
made this docker-only is gone.

It is still docker only, and the new reason is that there is nowhere to ask the
server. Three ways were tried against the real CLI, all with the real image:

- `-p 127.0.0.1::8080`, the form this uses so the runtime picks a free port, is
  rejected outright: `invalid publish host port: 127.0.0.1:`. There is no asking
  Apple's runtime to choose one.
- A port published at a number chosen here *is* listened on, and every
  connection to it is accepted and then reset. The runtime's log says why: its
  forwarder cannot connect to the container, `No route to host`.
- The container's own address — Apple's gives each one an address on
  `bridge100` — serves the diagram perfectly. `curl` fetched **the same 1595
  bytes** from `http://192.168.64.30:8080/plantuml/png/~h…` that this entry
  measured through docker. But not to this app: a plain `connect(2)` from a
  freshly built Swift binary to that address returns `EHOSTUNREACH`, and
  `URLSession` reports `-1009`, in the same second that `curl` from an approved
  terminal gets its picture.

The third explains the second: macOS's local-network privacy, which the
runtime's own helper is subject to as much as this app is. So the server starts
fine on Apple's runtime and draws fine — nothing about PlantUML or about
containers is the problem — and there is simply no address this app may use.
`canKeepWarm` therefore still returns false for `.apple`, and the reason written
there is now this one rather than the removal verb. Allowing local network
access to `container` in Privacy & Security is what would lift it; if it does,
this is a one-line change plus reading the address out of `container inspect`.

---

Its number is where it sits in the queue, not what it is worth doing next.
