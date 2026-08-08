# Say things in the corner instead of stopping everything

`58868c475` · 2026-08-01

A modal that opens on its own takes the keyboard, halts the window, and has
to be dismissed before the sentence inside it can be acted on — for news as
small as "no go.mod here". Pressing the debug button in a project that is
not Go did exactly that.

Errors are toasts now: bottom-right, stacked, gone in eight seconds, holding
while the pointer is on them. One line each, with the full story behind a
click — a dialog then is fine, because by that point it was asked for. Every
automatic alert in the app went this way: git failures, launch failures,
"cannot create that folder", save and open failures, clone failures.

What stays modal is what was always a question rather than an announcement:
"Delete this?", "Save changes?", "Which module?", the name prompts, the
breakpoint editor. Those are the answer to something just done, not an
interruption of it.

The debug button also stops guessing. It used to start a Go session
outright, which is where the go.mod message came from; with nothing running
it now offers the ways to start one, and Go is only among them when the
project is Go. Debugging a binary or attaching to a process no longer needs
a project open at all.
