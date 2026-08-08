# 36. Split the build into parallel modules

The build is slow enough to hold work up. AbydosApp is one target of some
hundred and fifty files, so every change recompiles all of it, and AbydosKit
is nearly as large.

Worth deciding first what the seams actually are rather than splitting by
folder. Candidates that look like real boundaries: the terminal (emulator,
pty, tmux, graphics — already almost self-contained), the editor and its
language support, git, and the run/debug machinery. The settings and theme
sit under all of them and would have to go somewhere they can be depended on
without pulling the rest in.

Measure before and after with the same clean build, and say the numbers.
