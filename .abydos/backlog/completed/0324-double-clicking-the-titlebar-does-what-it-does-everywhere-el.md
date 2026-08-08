# Double-clicking the titlebar does what it does everywhere else

`97e87854a` · 2026-08-06

The strip across the top of the window is a view this app draws — that is what
`fullSizeContentView` is for, and it is why the sidebar meets the toolbar. A
view swallows a double-click, so the one gesture every macOS window has did
nothing here, which reads as a window that will not zoom rather than as a click
that went nowhere.

What it does is the system's to say, in Settings ▸ Desktop & Dock: zoom,
minimise, or nothing. Read rather than assumed, because a window with its own
idea about this is a window that behaves unlike every other one on the machine.
Unset means zoom, which is what a Mac ships with.
