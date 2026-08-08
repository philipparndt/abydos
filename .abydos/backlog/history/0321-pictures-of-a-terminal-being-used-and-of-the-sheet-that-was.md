# Pictures of a terminal being used, and of the sheet that was described

`b37d40f39` · 2026-08-06

The terminal shot was one empty tmux window, which proves the tabs exist and
nothing about what they are for. It is a second window opened the way anybody
opens one, with a real build running in it and a file open beside it — and
what it prints is what `go build -v` prints, because it is that.

Three attempts, each wrong in a way worth writing down. `--type` types where
the keyboard is, and that was the editor, so the first version photographed
two tmux commands inserted into main.go. `-c "#{pane_current_path}"` is not
expanded by `new-window`, so the second built in a home directory and failed.
And the session outlives the app, so the third found the first run's window
still there and made another beside it — three tabs all called build.

The breakpoint sheet is photographed rather than described, with its values
coming out of a session file the same way anybody's would. Its fields also
centre their text now: a text view lays the first line against the top, so in
a box one line tall the text sat on the upper edge.
