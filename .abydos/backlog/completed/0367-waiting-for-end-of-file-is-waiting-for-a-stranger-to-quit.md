# Waiting for end of file is waiting for a stranger to quit

`483eca4b3` · 2026-08-07

The suite hung again, twenty minutes for something that takes fourteen
seconds. Sampling found a `git` blocked reading its stderr, and `lsof`
found the reason: two `/bin/cat` processes, left behind by a test twenty
minutes earlier, each holding five pipes rather than their own three.

Foundation does not mark a pipe's descriptors close-on-exec. Every
subprocess started while another is being set up inherits its pipes and
holds them open for as long as it runs, so end of file — which needs
every copy of the write end closed — can wait on a process that has
nothing to do with the one being run. In the app that is a language
server or a debug adapter outliving its session and quietly pinning a
`git` open.

Two fixes, either of which would have been enough and both of which are
right.

ProcessPipes now waits for the *program*, which is what it was actually
waiting for, then gives the readers a moment to drain what it left and
then takes the descriptors away from them. A truncated capture from a
program that has already exited beats waiting for a stranger.

And DAPClient.stop() now makes sure. `terminate()` is a SIGTERM and an
adapter is entitled to ignore one; dropping the reference afterwards left
it running with nobody to ask. It waits half a second and then does not
ask.
