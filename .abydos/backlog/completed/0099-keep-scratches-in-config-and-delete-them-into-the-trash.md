# Keep scratches in ~/.config, and delete them into the Trash

`3a329596d` · 2026-08-01

Two changes, both about a note surviving things that were not meant to
happen to it.

They now live in ~/.config/ideai/scratch rather than Application Support.
Not where macOS would put them, and deliberately so: what actually keeps a
file like this alive is somebody knowing where it is. ~/.config is a path
you can cd into, grep, and have already told your dotfiles repository or
your backups about. A folder nobody visits is a folder nobody notices going
missing. $XDG_CONFIG_HOME is honoured if it is set. Anything in the old
place is carried over at launch, collisions left alone rather than
overwritten, and the count is reported.

And nothing deletes a scratch outright any more — the pane's Delete and the
tidy-up of a scratch closed empty both put it in the Trash, so the answer to
"where did my note go" is somewhere it can be got back from. The
confirmation says as much.
