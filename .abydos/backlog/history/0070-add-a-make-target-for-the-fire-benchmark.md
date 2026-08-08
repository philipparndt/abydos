# Add a make target for the fire benchmark

`7b2834e37` · 2026-08-01

    make fire
    SECONDS=60 make fire
    PROJECT=~/dev/foo make fire

Builds the app and the benchmark, runs one inside the other, and prints what
it managed along with a screenshot of the fire — so a change to the terminal
can be checked in one command rather than six.

The pane the harness opens is small, and the figure is only comparable
against another terminal at the same size, so the target also says how to run
it full screen by hand.
