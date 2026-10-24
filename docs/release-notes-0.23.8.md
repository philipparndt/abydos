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
