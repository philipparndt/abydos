# Add "Open Terminal Here" to the navigator's context menu

`55fe2002d` · 2026-07-31

Opens a shell rooted at the clicked directory, or at the file's parent
when a file was clicked. Always a new session rather than reusing an
existing shell: the directory is the point, and a shell that is already
somewhere else — possibly mid-command — cannot honour it.
