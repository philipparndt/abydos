## ADDED Requirement: A program started in a pane begins with a signal state of its own

The program on the other end of a pane is a child of this process, and two
things it does not want are handed to it for free. A thread's *blocked* signal
mask is inherited by the child of a `fork` and kept across `execve`; a
disposition of `SIG_IGN` is kept across `execve` too. So without saying
otherwise, a shell in a pane starts life holding whatever the app happened to be
holding on the thread that started it.

Both halves are set back to the default between the fork and the exec: every
disposition to `SIG_DFL`, and the mask emptied.

It is not tidiness. This package ignores SIGPIPE process-wide and must — writing
to a pipe nobody is reading kills a process outright otherwise — and a shell that
inherited that ignores it in turn, so `yes | head` in a pane leaves `yes`
running rather than ending it. And a blocked mask is worse, because it makes the
pane's own controls stop working without failing: ⌃C and closing a pane both work
by sending a signal, and a signal that is blocked in the child is not refused, it
is queued for ever. A `/bin/cat` started from a thread with SIGHUP blocked
survives being terminated, is re-parented to `launchd`, and holds its
pseudo-terminal until the machine is restarted (item 0526).

### Scenario: closing a pane started from a thread that blocks SIGHUP

- **Given** a pane whose program was started on a thread with SIGHUP, SIGINT and
  SIGTERM blocked
- **When** the pane is closed
- **Then** the program receives the hangup and exits, and its pseudo-terminal is
  freed

### Scenario: a pipeline in a pane

- **Given** a shell in a pane
- **When** it runs a pipeline whose reader exits first
- **Then** the writer is ended by SIGPIPE, as it would be in any other terminal

## ADDED Requirement: A pane's pseudo-terminal is not handed to the next program started

A pseudo-terminal is freed when the last descriptor on either of its ends is
closed, and until then it counts against `kern.tty.ptmx_max` — 511 for the whole
machine, shared with every terminal, tmux and ssh on it. `openpty` answers with
two ordinary inheritable descriptors, so every program started afterwards —
another pane, a `git`, a language server — takes a copy of both and holds that
terminal open for as long as it runs. Closing the pane frees nothing.

So both ends are marked close-on-exec as soon as they are opened. The pane's own
program is unaffected: it closes the master itself, and `login_tty` puts the
slave onto its standard descriptors with `dup2`, which clears the flag on the
copies.

### Scenario: two panes, the first closed

- **Given** two panes, opened one after the other
- **When** the first is closed
- **Then** its pseudo-terminal is freed rather than held open by the second
  pane's program
