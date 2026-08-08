# Keep the terminal that is doing the navigating

`8b6abc478` · 2026-08-02

With the window following the shell, changing directory switched project —
and switching project closed the terminals and opened the ones the new
project had saved. The shell that had just been typed into was one of the
ones closed, which took the focus with it and left no way back.

A terminal is a place somebody is, not a property of the project. Saved
terminals are restored only into a window that has none; a window with
terminals in it keeps them across a switch.

Also: the run strip re-measures when the window is zoomed — it was the one
control on screen that stayed at the old size — and the capture harness can
choose a launch configuration by name, which is how the examples in
../ideai-examples get exercised.
