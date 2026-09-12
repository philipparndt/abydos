# Abydos 0.20.2

## The terminal at a trackpad's pace

Wheel events handed to a program, such as `less` or anything under tmux with
the mouse on, counted at least one line per event, and a trackpad raises
around a hundred a second. The trackpad's distance is added up now, one line
per cell covered. A mouse wheel is unchanged.

## Keys for the scrollback

⇧⇞ and ⇧⇟ page through the shell's history, ⇧Home goes to the oldest line
and ⇧End back to the prompt. A full-screen program still receives the keys as
before.

## Also in this release

A tick on a card can be undone: the task stays for a moment, dimmed, with
*Undo*, and ⌘Z takes it back. Every card copies its name from its menu, and a
card still being written offers the sentence that asks an assistant to finish
it.
