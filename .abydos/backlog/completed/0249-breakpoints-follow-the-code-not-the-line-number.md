# Breakpoints follow the code, not the line number

`0013f201c` · 2026-08-04

Typing above a breakpoint left it on its line while the code moved out
from under it, so the debugger stopped somewhere nobody had asked it to.
The document already tells tree-sitter which lines an edit took out and
put in; it now says so out loud, and breakpoints move by the same
numbers. One deleted with its line goes with it, and one that moves is no
longer claimed to be bound until the adapter says so again.

For a file changed by something that sends no edits at all — an agent
rewriting it, a checkout, a formatter — there is nothing to shift by, so
what is left to go on is the line itself: if the text that was on it is
still nearby, the breakpoint belongs there, searched outward so the
nearest match wins; if it has gone, the breakpoint stays put and stops
claiming to be bound.
