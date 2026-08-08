# Nothing waits for ever: on a runtime, on a container, or on the tests

`ac201b089` · 2026-08-08

Three hangs, one afternoon, and the same shape each time — something was
waited for that was never going to arrive.

`standardInput = Pipe()` reads as "nothing on standard input" and means the
opposite: this process holds the write end, so the child is handed an input
that never ends. Apple's `container` waits for that end — `container images
inspect` with a pipe held open answers after exactly as long as the pipe is
held, and never if it is held for ever — so the first question this app asks
about an image hung, taking the pane that asked with it. It is
`FileHandle.nullDevice` now, which is what the comment there always claimed.
The test stands in for a runtime with a script that reads to end of file, so
it needs no container and fails anywhere if this comes back.

A preview's deadline used to begin `guard let self`, so a pane closed while
a render hung left the render running and nothing left to stop it. Eleven
`container run` processes were found on this machine, the oldest a day old,
from app runs that had ended — and enough of them wedge the runtime's
service that every later question hangs too, which is what "it spawns
endless containers" turned out to be. The deadline now stops the process
whether or not the view is there to be told, and follows the polite ask with
a kill.

And `make test` runs under a ceiling. A test that hangs costs more than a
test that fails: the run says nothing, and the process actually stuck is not
the one being watched — `swift test` spawns a helper, which spawns the
bundle, so killing the top one by hand leaves the bundle running for ever
with nobody waiting for it. The whole run goes in a process group of its own
and the group is killed together, after five minutes by default, saying
which test had started last.

What is left of the container side is written down as backlog 395: nothing
reaps children when the app quits or crashes, nothing counts how many are in
flight, and a wedged runtime is still asked again rather than reported.
