# Run picker

## Why

The run dropdown is a flat `NSMenu`, and on a large Maven repository it runs off
the bottom of the screen and scrolls under an arrow. It is not long by accident:
the build section offers each goal against each module it could run in, so what
it prints is goals × modules.

Measured on a real reactor of 184 modules: **683 runnable things**, of which
nine are distinct choices. Four goals account for 676 of the rows. Two rows are
called `run Main` and two are called `run ServerApplication`, with nothing on
either row saying which module it belongs to — the module lives inside the name
of every row in the section, where it reads as noise.

And an `NSMenu` cannot be typed at, so there is nothing to do but scroll it.

## What changes

The dropdown becomes the popover the project pill and the branch pill already
are: a filter field, sections with headings, arrow keys and Return.

A goal that exists in many modules is named once, with a `184 places ›` chip;
opening it lists the places, the reactor root first. A goal in three places or
fewer is not folded — folding is for lists long enough to hide their
neighbours, and showing both `run Main` rows with their modules beside them is
what tells them apart.

Nothing about discovery changes. The four sources are the menu's own.

## Impact

- `RunConfiguration` gains `module`, kept apart from `name`.
- `MainWindowController.configurationMenu()` is deleted; `runList()` replaces it.
- An Xcode scheme's destinations stay an `NSMenu`, opened from the row: they are
  not known until Xcode is asked, which takes about twelve seconds.
