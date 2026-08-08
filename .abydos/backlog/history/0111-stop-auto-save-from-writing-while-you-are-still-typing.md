# Stop auto save from writing while you are still typing

`8358ce926` · 2026-08-01

Writing a second after every pause means everything watching the file — a
test runner, a bundler, a preview, GoSTL reloading a model — reacts to text
that is half-written, over and over.

IDEA's answer, adopted here: the idle timer is long (fifteen seconds, its
number), and the saves that matter do not depend on it. Switching away from
the window writes, running or debugging writes first, and ⌘S writes now.
Those are the moments something else is about to read the file; a pause in
typing is not one of them.

The delay is a setting, so anybody who wants the old behaviour can have it,
and the slider now goes far enough to be useful in either direction.
