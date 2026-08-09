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
  distinction, because nothing had ever stopped a server before.
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

## Left out of this item deliberately

- **An idle timeout.** The PlantUML server got five minutes (0422) because being
  wrong there costs one slow render. A language server restart costs a re-index,
  so this needs a different rule — probably only for projects not looked at in a
  long time, and never the front one. Its own item when somebody wants it.
- **Showing what is running.** A list of live servers and containers with their
  memory, and a way to stop one, is how somebody would have seen this without
  running `ps`. Also the fastest way to tell whether the three above worked. Its
  own item, and worth having.

---

Its number is where it sits in the queue, not what it is worth doing next.
