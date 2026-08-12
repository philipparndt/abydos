## ADDED Requirement: A pane shows what a command printed even if the command has already finished

A pane's process writes to a pseudo-terminal and the pane reads the other end.
On macOS those two are on a clock: **when a child exits, the kernel gives the
terminal's queued output 600 ms to be read, and then discards it.** The child's
own exit is what waits — it reaches `_exit` in under a millisecond and does not
become a zombie for another 600 — and when the wait runs out the controlling
terminal is revoked, the last descriptor on the child's end closes, and closing
it flushes the queue. Nothing is late at that point; the bytes are gone. (Linux
keeps them for the reader, which is why this is easy to write code that only
works there.)

600 ms is a long time and almost always plenty, which is what made this a
half-day of blaming the machine: the pane's reading queue normally takes the
bytes out within microseconds. On a machine with nothing to spare it does not,
and then a `/bin/echo` produces an empty pane rather than a late one. Everything
short is exposed and most of what this app runs through a pane is short — a run
configuration that prints one line and stops, a `git status`, the last of a
container build's progress, an agent that refuses and exits.

So the pane keeps a descriptor of its own on the child's end of the terminal, for
as long as the child runs. The queue is only flushed when the *last* one closes,
and the pane's is still open, so there is no deadline to lose a race against.

**It takes that descriptor before the child exists**, and the order is part of the
requirement rather than an implementation detail. Taking it afterwards — which is
what `forkpty` leaves you to do, since it closes the parent's copy before
returning — leaves a window in which the child can write, exit and lose its output
to a descriptor that is obtained a moment too late. The window is as long as this
process can go unscheduled, which on a loaded machine is longer than 600 ms. So
the terminal is opened, then the child is forked into it: there is no instant at
which a pane's output is unprotected.

This turns a lost-output bug into a lifecycle obligation, and that is the part
worth stating: with the deadline gone, **the child's exit waits for the pane to
read the terminal or close it** rather than for 600 ms. So the pane closes both
descriptors together, once, and only after the reader has finished with them —
and a pane that has stopped reading to apply back-pressure resumes before it
closes. A pane that shut its reader and walked away would leave the process alive
indefinitely, which is worse than the bug this replaced.

It also fixes the order things are announced in. The output a program leaves
behind is delivered before its exit is, because both go through the queue that
reads, and that queue is serial: nothing can announce an exit past a delivery
already in flight. A pane that showed a command's exit above its own output was
showing them in whichever order two queues got threads.

### Scenario: a command that has already finished, on a busy machine

- **Given** a pane running `/bin/echo hello`
- **And** a machine loaded enough that the pane's reader waits longer than 600 ms
  for a thread
- **When** the command has written its line and exited
- **Then** the pane still shows `hello`
- **And** it showed it before it reported the command exiting

### Scenario: a pane that stops reading while its command exits

- **Given** a pane that has suspended reading because it is behind
- **When** its command exits
- **Then** the command's exit completes once the pane reads again or closes
- **And** the pane leaves behind neither the process nor either descriptor
