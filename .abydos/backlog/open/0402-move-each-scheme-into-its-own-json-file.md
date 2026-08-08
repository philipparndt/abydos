# 402. Move each scheme into its own JSON file

The user's idea: one file per scheme, two sections — app and terminal — with
each colour given as a light/dark pair, so a scheme is data rather than four
places in two Swift files.

Today a scheme is spread across `Appearance.Family`, two `Theme` constants,
two syntax-colour functions and a `TerminalScheme` case with two
sixteen-colour tables. Adding Dracula touched all of them, which is the
argument for this.

Settle first: whether these ship in the bundle only or can be dropped into a
directory somebody keeps their own in; and what happens to a file missing a
colour, since a scheme that renders half-black is worse than one that is
refused.

---

Previously numbered 51, 391.
