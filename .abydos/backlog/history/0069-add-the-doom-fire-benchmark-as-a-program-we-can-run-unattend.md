# Add the DOOM fire benchmark as a program we can run unattended

`da57d1c59` · 2026-07-31

A port of github.com/const-void/DOOM-fire-zig, which has become the usual way
to ask a terminal how much it can take: every cell changes colour every
frame, so there is no redraw shortcut to be had.

Ported rather than driven, for two reasons. The original stops on a keypress,
which makes it useless in a script; and building it needs a Zig toolchain and,
at the moment, an unmerged pull request to work with Zig 0.16 at all. This one
runs for a given number of seconds and prints what it managed.

    swift build -c release --product firebench
    .build/release/firebench --seconds 20 --report /tmp/fire.txt

It reports the same number the original does — frames written over time
elapsed — which is the writer's view. A terminal that swallows bytes and
never paints scores beautifully on it, as ours did before the back-pressure
fix, so the number means something only alongside whether the fire moved.

It refuses to run into a pipe. Without a terminal there is no back-pressure
and nothing to measure, only several hundred megabytes of escape codes going
somewhere nobody will read them.

The random spread is seeded to a fixed value, so two runs differ because the
terminal did rather than because the fire did.
