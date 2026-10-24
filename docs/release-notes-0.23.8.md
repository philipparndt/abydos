# Abydos 0.23.8

## Folding a YAML list item folds only that item

Folding the first item of a YAML list used to fold the whole list, and the
first pair of a mapping folded the pairs below it. Each item now folds itself,
and the key above the list still folds all of it.

## A fold can always be opened again

Opening the only collapsed fold in a file turned its arrow back but left the
lines hidden. They now come back.

## A new tmux tab starts in the project, not at /

The + on the tmux tab strip opened its window at the root of the disk. It now
starts in the project's directory, and in the home directory when there is no
project.

## Open a board that lives on the vboard server

File ▸ Open vboard Board… lists the boards on the server named in Settings ▸
Tools ▸ vboard, filtered as you type, and opens the one you choose in a tab.
That tab is the live board, not a copy: edits are everyone's at once, there is
nothing to save, and closing the tab leaves the board on the server. File ▸
Save a Copy of the Board… writes it as a `.vboard`.

## A board takes the editor's colours on a classic vboard too

On a vboard server running its classic design, a board tab stayed navy and
indigo. It now draws in the editor's theme there as well.

## Opening some 3MF files no longer crashes

A 3MF whose part refers to a model file that could not be read, or to itself,
took the app down. Such a part is now left out and the rest of the plate is
shown.
