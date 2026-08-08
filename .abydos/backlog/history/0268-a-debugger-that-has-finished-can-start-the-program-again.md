# A debugger that has finished can start the program again

`a55a9876e` · 2026-08-04

Continuing a program that has ended means nothing, and the buttons for
stepping through it have nothing to step — so the toolbar was five
disabled controls and a sentence saying it was over. Getting back to where
you had been meant going up to the titlebar and starting again from there.

Once it is over, that row becomes the two things somebody standing here
wants: run it again, or debug it again. What they start is whatever the
play button in the titlebar would have started, so there is one answer to
"what does this project run" rather than two.

The pane also wears its state now. A debugger is a program somebody
started, the same as a run is, and its tab was the only one in a panel
full of them not saying so while it was going.

And a run or a debugger is bound to the project it belongs to. A window
that follows its terminal is somewhere else soon enough, and a stack frame
or a path in the output resolves against whatever tree the window happens
to be pointed at — so bringing one of these panes forward takes the window
back with it. Only when somebody reached for it, and only while the window
is following: panes are activated again while a project is being restored,
and following those would drag the window to wherever the last one was.
