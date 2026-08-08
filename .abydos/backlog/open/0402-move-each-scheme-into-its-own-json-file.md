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

## Decided

**Bundled schemes and a personal folder, from the start.** Not bundle-only with
a directory list left for later: the loader reads both, so somebody can drop a
scheme in without a build.

Which brings its own surface, and it is the work rather than the file format:
where a personal folder lives, what happens when a personal scheme has the same
name as a bundled one, whether a file dropped in is noticed without a restart,
and what a broken personal file does to startup — which must be nothing worse
than being ignored with a reason.

Still open: what a scheme missing a colour does. The recommendation stands —
refuse it, name the key and the file, fall back to a built-in — because
inheriting silently makes a forgotten key and an unread file look the same. A
test over the bundled schemes should fail in the suite rather than on screen.

---

Previously numbered 51, 391.
