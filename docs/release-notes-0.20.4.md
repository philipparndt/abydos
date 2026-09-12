# Abydos 0.20.4

## Web addresses in the terminal open on ⌘-click

Hold ⌘ over an address a program printed or marked as a link: it is
underlined, the pointer is a hand, and ⌘-click opens it. A bare click selects
text. Both renderers draw the underline now.

## Shift+Return breaks the line

Shift+Return sends the same newline Option+Return does, through tmux and
without it, instead of submitting.

## A TUI's highlights can be read under the Level AAA theme

Bold brightens a colour on the terminal's own ground only, not on a painted
background, and tmux is told the terminal shows true colour. k9s's selected
row and status bar read as sent.

## A completion listing scrolls instead of overwriting

Under the app's own engine inside tmux, a `cd`-tab-tab listing could leave
stale rows until a repaint. The alternate screen no longer counts discarded
history it does not have.

## A paste into a tmux terminal no longer leaks `[200~`

A missed tmux paste is retried, and if tmux cannot be reached the text is
pasted plainly, never with a bracketed-paste marker the shell did not ask
for.

## Returning to the settings page leaves the terminal alone

⌘, on an open settings page, or a window following its terminal between
projects, no longer un-maximises the terminal.

## A double-click on the tab strip is yours to choose

It expands and collapses the editor by default. A setting under *Editor*
gives back the old scratch-file behaviour, in the project or global.
