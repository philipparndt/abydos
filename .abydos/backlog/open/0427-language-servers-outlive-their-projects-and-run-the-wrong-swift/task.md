# 427. Language servers outlive their projects, and run the wrong Swift

Measured on the owner's machine while they were working, with two Abydos
windows open and four agents building in worktrees:

    swift-frontend processes            183
    of those, from Xcode's toolchain      9   ← the four builds
    of those, from swiftly's             ~174
    sourcekit-lsp processes                9
    of those, still spawning children      4
    resident memory, swift-frontend     15 GB

The machine was at a hundred per cent and the owner assumed it was the builds.
It was not: the builds are the nine. The rest is this app's own language
servers.

## Three faults, and the second is worse than the load

**They are not reaped.** Nine servers for two windows says nothing stops one
when its project is switched away from or its window closes. This is the same
shape as 0406 — a container outliving the app that started it — one floor up.
`ToolProcesses` already tracks them, and `track` is uncapped on purpose where
`adopt` caps at twelve, so the machinery to find and stop them is there; what is
missing is the moment that does it.

*This one is no longer read as a fault: reaping was built, measured, and then
reversed on purpose. What survives of it is the last line of the table below —
nothing outliving the app — and the rest is settled under "a language server
ends when the app does".*

**They are the wrong Swift.** The working servers run from
`~/Library/Developer/Toolchains/swift-6.1.2-RELEASE.xctoolchain` — swiftly's,
the toolchain the Makefile documents at length as older than the SDK, the one
that on the morning macOS 27 arrived could no longer compile Foundation. Xcode's
own `sourcekit-lsp` is in the list twice with no children at all, so the work is
going to the wrong one.

That costs more than processor time. The build uses one Swift and the editor's
diagnostics come from another, so **the errors on screen are not the errors from
the compiler**. A red squiggle that the build disagrees with is worse than a
slow machine, because it is believed.

**Possibly started twice.** Whether one instance can start two servers for the
same language and project is not established — `LanguageService` has `fetching`
and a `toolImages` cache that may already prevent it. Worth confirming rather
than assuming: if it does prevent it, the first fault above explains all nine on
its own.

## What to do, in this order — all three are done; the counts are below

1. **Stop a project's servers when the project goes** — switched away from,
   window closed, app quitting. `ToolProcesses.terminateAll` covers the exit;
   what is missing is the per-project case, and 0406's `atexit` lesson applies
   here too, since the command-line modes call `exit()` and run no cleanup.
   *Half of this was reversed the same day — only "app quitting" survives. See
   below.*
2. **Resolve every server through `xcrun`**, or through the same reasoning the
   Makefile's `SWIFT := xcrun swift` records, so the editor and the build agree
   about which Swift they mean. Check what else is found on the PATH the same
   way — this is unlikely to be the only tool resolved by luck.
3. **One server per language per project**, established by measurement rather
   than by reading.

## What the three came to, counted the same way

Driven by the harness on a scratch Swift package rather than by hand, and
counted with `pgrep -P` down from the app's own pid, so nothing below is any
other copy of this app. The path column is `ps -p <pid> -o comm=` — read off
the running server, not off the code that starts it.

    scenario                                   before   after
    one project open, servers settled               2       1
    switched to a second project                    4       1
    a second window on another project closed       2       1
    a .c and a .cpp open in one project             4       1   (clangd)
    left running after the app exited               1       0

    the running server's own path
      before  ~/.swiftly/bin/sourcekit-lsp
                → ~/Library/Developer/Toolchains/swift-6.1.2-RELEASE.xctoolchain/…
      after   /Applications/Xcode-beta.app/Contents/Developer/Toolchains/
                XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp

The doubled counts before are not two servers each: swiftly's `sourcekit-lsp`
is a shim that runs the real one as a *child*. So the app was tracking the
shim, and ending the shim orphaned the server underneath it — one was found
still running with `ppid 1` after the app had gone. Asking `xcrun` removes the
shim, and with it that whole failure: the process the app holds is now the
server itself.

Two more facts the counting turned up:

- **A window closing must sometimes keep the servers.** A torn-off window
  shares its project with the window it came from, so "this window is done with
  it" is not "nobody wants it". Measured: the torn-off window closed, and the
  project's server was still there afterwards. Nothing else in the app knew this
  distinction, because nothing had ever stopped a server before. *Sometimes has
  become always, and no window asks what the others are showing any more. What
  is left of it is in the key: two windows on one checkout, however the path is
  spelled, hold one server between them.*
- **The shutdown deadline did not work.** `shutdown` asked the server to stop
  and gave the ask two seconds — implemented as a task group racing a sleep, and
  a task group does not return until every task in it has, including the one
  parked on a reply that was never coming. Against a server that answers
  nothing, `shutdown` took as long as that server took to die on its own:
  measured at two minutes. Every request had the same deadline and the same
  hole, so a hung server hung whatever asked it. The deadline now belongs to the
  reply — it fails the pending handler — and the same measurement is 2.4
  seconds.

And one that was *not* a fault: an instance cannot start two servers for the
same project and the same language. `server(for:)` is on the main actor, and
the check, the `fetching` insert and the store all happen with nothing awaited
between them. What it could do was start two for the same *server*: the table
was keyed by the language asked about, and one definition answers for several —
clangd for `c`, `cpp` and `objc`, typescript-language-server for four. Two
`clangd` for one project, each indexing the same compilation database. Keyed by
the server now.

## A language server ends when the app does, and not before

The first of the three is reversed. Stopping a project's servers when its
window closed or the project was switched away from worked, and cost the wrong
thing: coming back to a project paid for its index all over again. A server is
now kept until Abydos itself goes — by every way it goes.

Counted the same way as everything else here: `pgrep -P` down from the app's own
pid, on two scratch Swift packages, driven by the harness rather than by hand.
The `reaped` column is the morning's; `kept` is the decision.

    scenario                                   before   reaped   kept
    one project open, servers settled               2       1       1
    switched to a second project                    4       1       2
    a second window on another project closed       2       1       2
    a .c and a .cpp open in one project             4       1       1   (clangd)
    left running after the app exited               1       0       0

The clangd row is item 3's and was not re-measured: nothing in it changed. The
rest were, on this build.

The last row is the one that cannot move, and it was measured down both exits.
The last window closed, which is `applicationWillTerminate`: two servers running
a moment before, none after. And a command-line mode that calls `exit()`, where
no delegate method runs at all and the `atexit` handler is the only thing there
is: a `sourcekit-lsp` was running right up to the moment the process went, and
nothing was left. Zero both times. That was the fault that opened this entry and
it has not come back.

`--switch-to` takes `path@seconds` now, because a switch one second in happens
while the first project's server is still starting, and a count taken after that
is a race rather than a rule.

**What it costs, plainly.** The 9 servers and 15 GB at the top of this entry are
what a session that opens project after project can collect again. That is the
trade, chosen rather than overlooked. Measured here, two projects kept two
servers at 32 MB each — but a four-line package is not where fifteen gigabytes
came from: `sourcekit-lsp` builds a real project in order to index it, and the
`swift-frontend` underneath is the weight.

Against that: switching back is instant, and the first project's server is the
same process afterwards that it was before, so nothing re-indexes. An editor
that goes quiet for a minute every time somebody changes project is worse than a
leak — as long as the leak can be seen, which is the next section and is the
condition on this decision rather than a nicety beside it.

## What this decision needs next: show what is running — built

Promoted out of "left out" below, because the decision above is what makes it
necessary. A list of the live language servers and containers with their memory,
and a way to stop one, is how somebody sees a session that has collected nine of
them and does something about it — without running `ps`, which is the only
reason this entry exists at all. It is the mitigation for the cost above.

It is View ▸ Running Servers and Containers, a window of its own, and it is
built. The window controller's own comment weighs the three shapes it could have
had; the short of it is that what it lists belongs to the *application* — one
`LanguageService` and one `ToolContainers` however many project windows are open
— so a panel tab in a project window would have shown the same servers twice.

**The number in it is the subtree, and that is the whole point.** A row's memory
is the process and everything it started, because the figure that would have
been easy to show is the one that would have made this view worse than nothing:
measured on a four-line Swift package, `sourcekit-lsp` alone is 32.7 MB; the
same server on this repository reads 410.8 MB across itself and three processes
it had started, and the count is printed beside the number so nobody has to
wonder where it came from. The fifteen gigabytes at the top of this entry lived
in those children, never in the server.

The second line of a row is the executable `ps` resolved, which is this entry's
second fault made permanently visible: on this machine it now reads
`/Applications/Xcode-beta.app/…/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp`,
and the day it says `~/.swiftly/…` again, somebody will see it.

**Stopping one, measured.** `LanguageService.shutdown(server:)` is what a row's
Stop calls — this is what `shutdown` was kept for, and it is now one server at a
time rather than a whole project. Driven by the harness on a scratch package,
`--stop-running sourcekit`:

    the list before               sourcekit-lsp, lsprobe, 8s, 32.7 MB, pid 76094
    after Stop                    empty
    pid 76094 alive afterwards    no
    after a file needed it again  sourcekit-lsp, lsprobe, 7s, 29.2 MB

The last line is the half that was easy to leave unproven, and it did not work
at first. **A server stopped by hand could not come back.** The list went empty
and stayed empty, and the fault was not in the stopping: `LSPClient.onExit`
removed the table entry *by key*, and the key is filled again by the new server
before the old process has finished dying. The old server's exit then deleted
the new one, leaving the app with a running language server it no longer knew
about — the exact shape of leak this entry is about, introduced by the thing
meant to show it. `onExit` now removes the entry only if it is still holding
that very client. Nothing else called `shutdown` before, which is why this had
never happened.

**Containers, measured on Apple's runtime.** Opening the examples repository at
its Python devcontainer subproject gave four rows, and three of them are
different cases — a server on this machine, a server inside somebody else's
container, and the container:

    gopls                | abydos-examples          | 354,9 MB +1 | ~/go/bin/gopls
    openscad-lsp         | abydos-examples          |   4,1 MB    | ~/.cargo/bin/openscad-lsp
    pyright-langserver   | python-language-server   |     —       | in abydos-devcontainer-50919-1
    Dev container        | abydos-devcontainer-…    | 142,6 MB    | abydos-devcontainer:python-…

The dash on the third row is deliberate and was got wrong first. A server inside
the project's devcontainer is a `container exec` out here — 29 MB of client —
and the whole of itself in there. Showing the 29 would have been this entry's
own mistake repeated one floor down, and showing the container's 142.6 would
have counted the same memory twice, since the row below is that container and it
is shared with the terminals and the build. So the row says where it lives and
declines to put a number on it. It is also why that pair is two rows and not
one: a server with a container of its own is one row, because stopping the
server is stopping the container; a devcontainer belongs to the project and
outlives any one server in it.

Stopping the container row was measured too: `--stop-running devcontainer` took
`abydos-devcontainer-24230-1` out of the list, and `container ls --all`
afterwards had no trace of it, while `gopls` and `openscad-lsp` were still there
and untouched.

**What it costs to look.** One `/bin/ps` for the whole machine rather than one
per row, and at most one pair of runtime commands per container runtime. It
refreshes when somebody looks at it — opening it, bringing it to the front,
pressing Refresh, and stopping something — and there is no timer, because
`docker stats` is about a second of a runtime's attention and a window that
spent that every few seconds to show what is wasting the machine would be a joke
at the owner's expense. `--no-stream` is on both `stats` commands and there is a
test that says so: without it the command never returns, which is the shape of
process 0406 and this entry exist to stop this app leaving behind.

**What is not proved.** Docker's half is driven live against a container the
test starts and owns. Apple's is not: both its commands were read off `container`
1.2.2 by hand, and the transcripts in the tests are those answers, but nothing
in the suite runs them. A test that asked both runtimes whether they accept
these commands was written and then removed — with no container of its own it
asked about every container on the machine, and this suite starts and removes
containers in parallel, so it failed on a busy run rather than on a wrong flag.
A test people learn to ignore is worse than an admitted gap.

Three smaller things the measuring turned up, each now written down where it
happened:

- `docker stats` answers about a *stopped* container rather than refusing —
  `0B / 0B`, on docker 29.1.4. A row would have read as running and free, so the
  runtime's own status word is read and shown when it is not "up".
- Apple's runtime reports `status.startedDate` beside `configuration.creationDate`.
  They are a second apart on the containers this app starts and much further
  apart on a container that was stopped and started again, so the row uses the
  first.
- `ToolContainers.release` waits up to ten seconds for a runtime to answer, and
  the Stop button was calling it on the main actor. A window whose subject is a
  machine that has stopped responding must not itself stop responding.

**Driving it.** `--running-tools` opens the list and prints what it says;
`--stop-running <text>` presses Stop on the first row matching and prints the
list before, after, and once more when a file has asked for a server again,
along with whether the operating system still has the stopped pid. With no
`--screenshot` the run ends when the reading is done and `--delay` becomes how
long to let things settle first — which a server that indexes needs, since the
processes underneath it arrive after it does.

## Left out of this item deliberately

- **An idle timeout.** Decided rather than deferred: there is not going to be
  one. It is the same question as the one above, answered a slower way. The
  PlantUML server got five minutes (0422) because being wrong there costs one
  slow render; being wrong here costs a re-index, and what stops a session
  collecting servers is somebody seeing them and stopping one, not a clock.
- **Showing what is running.** Moved up — it is the mitigation this decision
  rests on, and it has a section of its own above, where it is now built.
- **Everything else in `ToolProcesses`.** The list shows language servers and
  containers, which is what this entry asked for, and not the rest of what that
  register holds. The reason is that it holds bare `Process` objects with no
  record of what any of them is for: a row saying only "a process" with a Stop
  beside it is worse than no row. Everything long-lived in there is already
  listed by its owner — a language server by `LanguageService`, a container by
  `ToolContainers` — so what is missing is the short-lived renders, which are
  the ones nobody needs to see. If the runaway that `adopt`'s cap of twelve
  exists to stop ever needs looking at, this is where it would go, and it would
  need each process to arrive with a sentence about itself.
- **Anything automatic.** No sorting by size, no highlighting of the expensive
  one, no warning when the total passes a number. The list is short and the
  numbers are in it; what to do about them is a person's decision.

---

Its number is where it sits in the queue, not what it is worth doing next.
