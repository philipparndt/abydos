# Every Makefile goal can be chosen, and choosing starts nothing

`218431330` · 2026-08-04

Picking a goal from the run menu did nothing at all when the goal had
been listed as debuggable but no plan could be made for it at click time
— the handler returned on a guard, leaving no selection and no word about
why. Whether a goal is debuggable was decided when the menu was built and
acted on later, which is how the two came to disagree.

There is one action for all of them now, and it always answers: a goal
that can be debugged becomes a launch configuration, and every other goal
becomes `make <goal>` in the terminal, selected and waiting for the play
button. This area has broken twice, so the rule is `MakeLaunch.choice`,
in the kit, with tests: every goal yields something, an unknown goal
yields a run that make itself will refuse, and nothing a choice returns
has been started.

Also from using it: Terminal is the first settings page, the three tmux
switches are a group under a heading of their own, and a switch that
cannot be used greys its name and its sentence as well as its control —
a disabled checkbox on its own reads as one somebody has not turned on.
