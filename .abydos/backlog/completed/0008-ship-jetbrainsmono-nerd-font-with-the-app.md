# Ship JetBrainsMono Nerd Font with the app

`50d9bd57b` · 2026-07-30

Prompt themes like starship and powerlevel10k draw their separators with
Private Use Area glyphs. On a machine without a Nerd Font those render as empty
boxes, so relying on what the user happens to have installed is a bad default
for something this visible. Ghostty ships a font for the same reason.

Four weights of JetBrainsMono Nerd Font Mono are bundled and registered at
launch with process scope, so nothing is installed system-wide and nothing is
left behind on quit. OFL 1.1, license included alongside. It is now the default
for both the terminal and the editor, which also gives them a common typeface.

Note that NSFontManager.availableFontFamilies does not list process-registered
fonts. The cascade list was filtering against it and therefore silently dropping
the very font being shipped; the fallbacks are now listed unfiltered, since a
descriptor for a missing family is skipped harmlessly when resolved.
