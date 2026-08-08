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

## Done

**A missing colour refuses the file**, and the reason names the key and the
path: `…/nord.json: app.syntax.keyword is missing — the file is ignored`. It
goes to `~/Library/Logs/Abydos/schemes.log`, and whatever the file would have
replaced stands in its place. Both halves of every pair are required, and so is
`#RRGGBB` — half a colour is as bad as none, since a scheme that only says what
it looks like in the dark goes wrong the first morning somebody opens the
curtains. `BundledSchemeTests` reads the shipped four, so a colour dropped from
one of those fails in the suite rather than on screen.

**Personal schemes live in `~/.config/abydos/schemes`** —
`$XDG_CONFIG_HOME/abydos/schemes` when that is set. A path already in a dotfiles
repository rather than one inside a bundle an upgrade replaces.

**A personal file with a bundled `id` replaces it**, keeping the place in the
list the bundled one had unless it states an `order` of its own. That is the
only way to adjust a shipped scheme; the alternatives — refusing it, or listing
two schemes with one name — are worse than the rule being written down.

**A file dropped in is noticed at the next launch, not before.** Both
directories are read once at startup: `SchemeLibrary.reload()` exists and is
cheap, but the settings window builds its rows once and keeps them, so calling
it there would only look like it worked. Not watched either — a scheme is not
edited often enough to have a file watcher running all day.

**A broken file cannot stop the app.** It is skipped with its reason; a
directory that is not there is the ordinary case rather than an error; and if
nothing at all can be read there is a grey `Scheme.fallback` to draw a window
with, which is deliberately nobody's taste so it reads as "the schemes did not
load" rather than as a palette somebody chose.

Two things fell out of the port that were not in the question. `Appearance` no
longer knows which palettes exist — the list is whatever has an `app` section —
so a scheme file states the names the setting holds for it, defaulting to
`nord`, `nord-light`, `nord-system`; only `blue.json` says otherwise, because
its three were `dark`, `light` and `system` before this app had a second
palette. And "Editor colours" became the first scheme with no `app` section at
all: a terminal palette that says `"follows": "editor"` for its ground, text and
cursor while stating its own sixteen. It answers to `dark` as well, which is
what the setting called it while these were an enum.

The format is written down in `Sources/AbydosKit/Settings/Schemes/README.md`,
which ships inside the app beside the files it describes.

---

Previously numbered 51, 391.
