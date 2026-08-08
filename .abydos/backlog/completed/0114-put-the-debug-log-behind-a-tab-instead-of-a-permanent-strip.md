# Put the debug log behind a tab instead of a permanent strip

`abc8ee58c` · 2026-08-01

The console had a fixed band along the bottom of the pane whether or not it
had anything to say, taking room from the stack and the variables — which
are what you are actually reading while stepping.

It shares the right-hand side with the variables now, behind two tabs. The
stack stays where it is, since picking a frame is what you do before reading
anything.

A hidden log has to say when it has something, or a build error is invisible
behind a tab nobody had a reason to press: output arriving while the
variables are showing puts a dot on the Console tab, and a launch that never
starts switches to it outright, since then the log is the only thing worth
looking at.
