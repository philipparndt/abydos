# 414. A scheme dropped into the folder waits for the next launch

Schemes are files now (0402), and `~/.config/abydos/schemes` is where somebody
keeps their own. The folder is read once at startup, so a file written while
the app is running is not there until it is restarted — and the person writing
it is, by definition, sitting in front of the app trying colours out.

`SchemeLibrary.reload()` exists and does the right thing. What is missing is
somebody calling it and something noticing afterwards: the settings window
builds its rows once, so calling `reload()` from there would repopulate the
library and leave the list on screen exactly as it was. That is worse than not
offering it, because it looks like it worked.

## Decided

**Two small buttons beside the theme selector: a reload, and a reveal.** This
does not happen often enough to watch the folder for — a `DispatchSource` on a
directory to catch something somebody does a handful of times in a year is
machinery that has to be right for ever in exchange for saving one click.

- **Reload** — the two-arrows glyph, `arrow.triangle.2.circlepath`. Calls
  `SchemeLibrary.reload()` and then rebuilds the list *and* the window, which is
  the part that has to actually work: `reload()` alone repopulates the library
  and leaves the settings rows exactly as they were, which looks like it worked
  and is worse than not offering it.
- **Reveal** — opens `~/.config/abydos/schemes` in the Finder, and creates the
  folder if it is not there yet. Somebody who has never written a scheme has no
  folder, and a button that opens nothing is a bug report.

That also answers the parse-failure question below without a message that
appears and clears while somebody types: the reload is a moment they chose, so
a file that will not parse can be said plainly then — named, with the key that
is missing — beside the button that was just pressed.

**Worth deciding:** whether a file that fails to parse while being edited
should say so on screen rather than only in `~/Library/Logs/Abydos/schemes.log`.
Half-written JSON is the normal state of a file somebody is typing into, so
this would be a message that appears and clears constantly — probably a line in
the settings page rather than anything modal, and probably only for the scheme
that is selected.

**Worth deciding:** whether a file that fails to parse while being edited
should say so on screen rather than only in `~/Library/Logs/Abydos/schemes.log`.
Half-written JSON is the normal state of a file somebody is typing into, so
this would be a message that appears and clears constantly — probably a line in
the settings page rather than anything modal, and probably only for the scheme
that is selected.

---

Its number is where it sits in the queue, not what it is worth doing next.
