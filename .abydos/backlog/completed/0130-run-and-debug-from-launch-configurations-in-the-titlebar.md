# Run and debug from launch configurations in the titlebar

`8109e3e9b` · 2026-08-01

VS Code's launch.json, because most projects already have one. Pressing
play with none writes the obvious configuration and says so, rather than
asking a question nobody can answer before the first run.

Arguments, working directory and environment are editable in a panel of
the app's own; a system alert would have drawn light chrome in front of a
dark window. Unknown keys in the file survive the round trip.
