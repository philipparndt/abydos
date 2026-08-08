# The panel's tabs start where the panel does

`96d071533` · 2026-08-06

tmux's strip was already hard against the left, for a reason of its own: the
active tab is a hole cut in the green, and green showing down its outer edge
frames that one tab. Ours began eight points in, which was invisible until the
terminal below it lost its own margin — and then the strip sat on nothing,
indented above text that starts at the edge.
