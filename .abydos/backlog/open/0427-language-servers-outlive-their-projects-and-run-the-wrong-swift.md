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

## What to do, in this order

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
