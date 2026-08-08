# Open a terminal tab with ⌘T, while in the terminal

`2cf97140e` · 2026-08-01

The key everybody's fingers already reach for, and only where it means
something: while the keyboard is in the terminal it opens another tab, and
anywhere else in the window it is not taken at all. ⇧⌘T still opens one from
wherever you are.

Scoped by the menu item validating against where the keyboard actually is
rather than by intercepting the key, so the shortcut stays visible in the
menu, stays remappable, and greys out when it would do nothing.
