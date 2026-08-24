# Abydos 0.6.1

Three commits, and all of them are about a name. The app stopped calling itself
`ideai` in 0.6.0's wake — and the development pod, which is half of the app and
lives in a different language, did not hear about it. This release is the other
half of that rename, and it is **breaking on purpose**.

## The dev pod catches up with the rename

The rename changed the names the app *writes down*: the prefix on the extras it
owns in a `launch.json`, its queues, its notifications, and the label it puts on
a pod. It changed none of `DevPod/`, because `DevPod/` is Go and Helm and a
Makefile and nothing there is compiled against anything in `Sources/`. Nothing
failed to build. Two things quietly stopped agreeing.

**The app could not find a pod installed by its own chart.** `DevPods.list`
asks `kubectl` for pods labelled `abydos.dev/devpod=true`. The chart shipped in
the same commit still wrote `ideai.dev/devpod`. The release notes for 0.6.0 say
a pod installed by an *earlier* version is not found and a second one is
installed beside it — which was a decision, taken deliberately. This was not
that: the chart in the bundle wrote the old label too, so a pod installed by
0.6.0 was invisible to 0.6.0.

**The other half was broken the other way and got away with it.** Where a
project runs inside its own chart, the app patches a container and sends the
supervisor `ABYDOS_BINARY`, `ABYDOS_WORKDIR`, `ABYDOS_CONTROL_ADDR`,
`ABYDOS_DEBUG_ADDR` and `ABYDOS_DLV`. The supervisor read `IDEAI_*` and had
never heard of any of them. It worked — every one of those five values is
identical to the default the supervisor falls back to, so the setting and the
absence of the setting were the same thing. It would have stopped working the
first time anybody changed one.

Both halves now say `abydos`:

- The chart labels pods `abydos.dev/devpod`, and the app looks for that.
- The supervisor reads `ABYDOS_CONTROL_ADDR`, `ABYDOS_BINARY`, `ABYDOS_WORKDIR`,
  `ABYDOS_DEBUG_ADDR`, `ABYDOS_DLV`, `ABYDOS_GDBSERVER`, `ABYDOS_JAVA`,
  `ABYDOS_AUTOSTART` and `ABYDOS_ARGS`.
- The binary in the image is `abydos-supervisor`, and so is the entrypoint and
  the command the container patch overrides it with.
- The images are `pharndt/abydos-devpod`, with the same four tags as before:
  `dev`, `dev-go`, `dev-native` and `dev-jvm`.
- The Go modules are `github.com/philipparndt/abydos/devpod/...`.

### What this breaks

**The image moved.** `pharndt/ideai-devpod` is not updated any more. Anything
pinned to it — a `values.yaml`, a running deployment, a launch configuration
with an explicit image — keeps working against the old published tags and stops
receiving anything new. Point it at `pharndt/abydos-devpod` and it is current
again.

**Old images and this app do not mix.** The entrypoint in an `ideai-devpod`
image is `/usr/local/bin/ideai-supervisor`; the container patch this app writes
names `/usr/local/bin/abydos-supervisor`. That is why all four variants were
republished together rather than one at a time.

**A pod installed by an older version is still not found.** That was true in
0.6.0 and is true here, for the same reason and by the same decision: the label
is not read in both spellings. Uninstall the old release, or delete the pod, and
install again.

The Helm *release* prefix is deliberately untouched and still `ideai-`: it names
releases that exist in somebody's cluster, and renaming it would orphan them.

## A test that took the whole suite down with it

`GitStashLiveTests` asserted a stash list had three entries with `#expect`, then
subscripted the third on the next line. `#expect` records a failure and carries
on. Under load the assertion was the one that failed — `git` did not spawn, the
result came back with exit code -1 and no output, the list came back empty — and
the subscript trapped.

A Swift array trap is not a test failure. It is `SIGTRAP` to the process, and
the process is the whole test bundle: one flake ended a run with sixty-two
suites still in flight, every one of them reported as a failure of its own. It
took a crash report to find, because the log named sixty-two suspects and not
the one that did it.

`try #require` stops that one test and lets the rest finish. Nothing in the app
changed — a bundle that dies is a bundle, not a shipped binary — but a red run
that blames sixty-two innocent suites costs an afternoon.

## Also

The commit the About window reports is right again. `AppDelegate` read
`IdeaiCommit` from the bundle while `Scripts/bundle.sh` had been writing
`AbydosCommit` since the app was renamed, so every build since then has called
itself `unknown`.

Remembered window layout survives the rename. The autosave names moved with
their saved values copied onto the new keys, once, and only where the new key
was absent — a bare rename would have put everybody's window back to its default
size with both dividers in the middle, and nobody would have connected that to a
rename.

The shipping bundle identifier is still `de.rnd7.ideai`. It is the App Store
identity, and macOS files the Local Network grant under it.
