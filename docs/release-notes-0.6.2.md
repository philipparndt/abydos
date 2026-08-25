# Abydos 0.6.2

Twenty commits, and most of them are the app getting out of the way on a big
project. A debug run that sat for a minute and a half before it started. A
right-click that took seconds. Four language servers indexing at once and
stalling the main thread for a hundred and four seconds while doing it. None of
these were visible on a small checkout, and all of them were unmissable on a
large one.

## Waiting for things that were never necessary

**Pressing Debug on a large Java repository sat on "Looking for the class to
debug…" for a minute and a half.** Measured on 13,754 sources: 96–139 s, of
which reading the files was 2.5 s. The rest was splitting every file into lines
and running `contains("main(")` — a Unicode canonical-equivalence search — over
about a million of them.

The anchor never needed a main class. It names a module, and jdtls answers
about whichever project the file it is handed belongs to. Finding one file from
a few stats costs 0.9 ms against a walk of the whole tree.

**A right-click in the file tree took seconds**, for a context menu whose slow
part was a submenu of five items. Working out which kinds of file to offer under
New collected every file in the project — inside `menuNeedsUpdate`, which AppKit
calls on the main thread while the menu is on screen waiting. It was cached, and
the cache was the other half: the filesystem watcher cleared it on any change
worth rescanning for, so the walk was paid again on the first right-click after
every save. On a checkout of 43,600 entries, that is a right-click nobody wants
to use twice.

**Background indexing no longer takes the whole machine.** A language server is
kept for every project that has been opened, which is right — moving between two
projects should not pay for a server start each time. What that did not price is
that each server indexes on its own account and fans its build out to every
core. On a fourteen-core machine: four live servers, one running `swift-build`
at `-j14` with thirteen `swift-frontend` under it, against a 9.7 GB tree whose
every write the endpoint-security filter scans. The main thread stalled for
104 s, 54 s and 22 s at 1% CPU — not computing, but queued behind the app's own
indexer.

**The dependency section resolves its paths once.** `realpath(3)` on every node
and every package path, on every call, keeping none of it — some sixty syscalls
before a row was drawn on a project with thirty checkouts. Sampled during one of
the stalls above, 431 of 434 main-thread samples were inside that walk. The app
cannot make the security filter faster; it can stop asking it the same question.

## Editing and the terminal

**A line typed wider than the pane could not be scrolled to.** The view's width
was measured when the file was opened and afterwards only by search and
jump-to-line; ordinary editing never touched it. So text *typed* or pasted wider
than anything the file held at load left the view exactly as wide as the pane —
no scroll range, no scroller, no way to reach what had just been typed. Nothing
about scrolling was broken, which is why it took a while to find.

**A new terminal starts at the width the pane actually has.** A debug run
printed its VM options folded at eighty columns down the left of a pane half
again as wide, and no resize straightened it. Every wrap at exactly eighty is
what gives it away — a wrap at the pane's own edge lands on whatever column that
edge falls on, not on a round number left over from a hardware terminal. The
emulator was built at 24×80, and a pane that starts before it is laid out keeps
what it was built with.

**⌃Space asks for completions, and a cold server says so.** A list already
appeared while typing, but only after two letters or a character the server asked
to be woken by — which left the case people most want help with unanswerable: a
caret in the middle of nothing, where the question is "what can go here at all".
On an empty line in a Swift file that returns 20 items where the typing rule
returned none. And where the server is not ready yet, that is now on screen
instead of nothing happening.

## Debugging

**A watched value can be opened up.** A watch on anything but a scalar was a row
saying `{...}` with no way in. The session had been storing the reference since
watches were written; there was simply no way to address the root of a watch, so
nothing ever asked what was behind it.

**The JVM option variables ask the shell what it has first.** Debugging a script
writes `JAVA_TOOL_OPTIONS` to carry the JDWP agent, built from this app's own
environment — which, for an app launched from the Finder, is launchd's, not the
one a login shell builds from somebody's profile. The variable looked unset, so
the plan wrote it as if starting from nothing, and `env VAR=…` in front of the
command then replaced whatever the shell would have supplied.

## The project view and git

**A chain of single-directory folders is one row.**
`src/main/java/com/example/myapp` is five rows before any code, four of them
saying only "there is one more folder inside me", and a reactor of fifty modules
pays that fifty times. Folded, it is `com.example.myapp` under a source root.
Off by default: the tree changes shape under this, and a change of shape nobody
asked for is one they undo before they can work.

**A fast-forward that worked is not an error.** Fast-forwarding a branch that is
not checked out did exactly what was asked and then came up in red, under a
window titled Error. Every outcome took the default toast kind, so success and
failure were indistinguishable — and the one people meet most often is success.

## The last place the old name reached a cluster

0.6.1 moved the whole of the development pod to abydos and deliberately kept the
Helm release prefix: a release names something that exists in somebody's
cluster, and renaming it orphans that rather than migrating it.

That trade is taken now. A deployment installed from an abydos chart, carrying
abydos labels, running an abydos supervisor, was still called:

    ideai-go-service-abydos-devpod-d8b5785d5-kd442

Half a rename reads as a bug every time somebody runs `kubectl get pods`, and
what it was protecting was one `helm uninstall`. The release for a project is
now `abydos-<project>`.

**What it costs:** a pod installed by an earlier version is not upgraded. The
new release is installed beside the old one, which keeps running until it is
removed:

    helm uninstall ideai-<project> --namespace <namespace>

Both are found while both exist — they carry the same label — so it is a
duplicate in the list rather than a pod nothing can see.

The Namespace field on a launch configuration suggests `abydos-dev` now. It was
the last `ideai` left anywhere a person looks.

## Also

Four tests could take the whole suite down with them. Each asserted something
with `#expect` — which records and carries on — and then, on the next line,
subscripted or force-unwrapped the thing it had just asserted about. Under load
the assertion was the one that failed, and the unwrap trapped; a trap ends the
process, so one flake was reported as every suite still running failing at once.
It took a crash report to find the first, because the log named sixty-two
suspects. `GitStashLiveTests`, `GitBranchesTests`, `ProjectGitRaceTests` and
`BacklogRunnerTests` all use `try #require` now.

The images are unchanged: `pharndt/abydos-devpod:dev`, `:dev-go`, `:dev-native`
and `:dev-jvm` are the ones 0.6.1 published. The release name is computed by the
app and handed to Helm, so nothing in the chart or the image moved.
