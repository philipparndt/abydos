# Abydos 0.20.5

One fix, from a report the same morning: a link a program styles is a link
here too.

## A styled link a program writes is a link in the pane

Claude Code's `#211` for a pull request, and anything else a program marks as
a hyperlink with OSC 8, arrived in a pane as plain text while Ghostty
underlined it. The pane already understood such links; they never reached it.
tmux forwards a hyperlink only to a client whose terminal has said it shows
them, and the client this app starts had not said so — it does now, beside the
true-colour flag it already carried. A pane without tmux was the other half:
Claude Code writes these links only for a terminal it recognises, or one that
says `FORCE_HYPERLINK`, and a pane of ours now says that in its environment
rather than claiming to be a terminal it is not.

## A styled link shows its hand, its address and opens on a click

A link the program marked is underlined and the pointer is a hand as soon as
the pointer rests on it, no ⌘ needed — the program has already said it is a
link. Rest a moment longer and a tooltip says where it goes, since `#211` on
its own does not. A plain click opens it; a press that drags away still selects
text, and Shift still forces a selection, so nothing about copying from a pane
changes. A plain web address a program printed keeps the rule from 0.20.4: it
shows itself under ⌘, and ⌘-click opens either kind.
