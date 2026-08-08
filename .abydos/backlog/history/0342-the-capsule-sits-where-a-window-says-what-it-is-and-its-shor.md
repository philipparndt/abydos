# The capsule sits where a window says what it is, and its shortcut leaves the terminal alone

`ff29f0f6d` · 2026-08-07

Left of the titlebar rather than centred: the eye starts at the top left of a
window, and the one thing answering "where am I" should not be somewhere to go
looking for. Taller, too — the drawn shape is the intrinsic height less the
inset at each end, so a 30-point item was a 22-point capsule, which read as
something that had shrunk.

⇧⌘K opens it, from the File menu so it works wherever the focus is. Not plain
⌘K: that clears the terminal, as it does in Terminal and every console, and a
menu's key equivalent is matched before any view sees the key — taking it would
have quietly stopped that working.
