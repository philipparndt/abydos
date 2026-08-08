# Watches, conditional breakpoints, goroutines, and copying values

`e40f284f3` · 2026-08-01

Four things a debugger needs before it is one you would choose.

Watch expressions. A field above the variables takes any expression and
keeps it: `answer * 2` is as good as a local. They are re-read after every
stop and every frame change, since an expression means something different
in each, and one that does not compile in this frame says "not available
here" rather than clearing — it is out of scope, not wrong.

Conditional breakpoints. Right-click one in the gutter for a condition, a
hit count, or a message to log instead of stopping. A breakpoint you have to
sit and press Continue at four hundred times because the interesting case is
the last one is not much of a breakpoint. Conditions survive between
sessions and can be set before the first launch, which is when people
actually set them — the pending set now holds whole breakpoints rather than
line numbers, which is what dropped them before. A conditional one is ticked
in the gutter, because "why did it not stop" is answered by remembering
there is a condition on it.

Goroutines. A picker above the stack lists them and switches between them.
Go programs have thousands, and the one that hit the breakpoint is rarely
the only one worth reading — a deadlock is a question about the others.
Switching shows that stack without moving the execution marker, since
nothing has stopped.

Copying. Right-click a variable or a watch for its value, its name, both, or
to start watching it.

Verified against Delve: `number == 3` stops on the third iteration where the
same breakpoint without it stops on the first; watches evaluated a slice, an
arithmetic expression and an out-of-scope name correctly; six goroutines
listed and switched between.
