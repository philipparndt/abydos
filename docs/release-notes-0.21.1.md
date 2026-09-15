# Abydos 0.21.1

## The project search replaces what it found

⇧⌘R opens the search pane with a replace half: what the matches should become,
**Replace** for the rows you have selected — a file heading takes its whole
file — and **Replace All** for every row showing. Rows hidden as done are left
alone. Each file is one edit made against its current text: an open tab takes
it as its own, a closed file is written on disk, and one ⌘Z in the list takes
the whole replacement back. With `.*` on, `$1` is a capture, and a template the
pattern cannot use is refused. Review Branch… gave up ⇧⌘R and keeps its menu
item.

## The window says when git cannot run

After an Xcode update, `/usr/bin/git` refuses every command until the licence
is accepted — and exits 0, so nothing looked wrong except that every project
asked to be trusted again and the git pane was empty. A strip across the top
of the window now says git cannot run, why, and the command that fixes it,
with a button that copies it. It goes by itself when git runs again, which the
app checks the moment it comes back to the front; a project whose remote could
not be asked is left undecided rather than shown as untrusted.
