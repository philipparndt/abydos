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

So this is two things, and the second is the real one:

- **Notice the file.** A `DispatchSource` on the folder, or a re-read when the
  settings window becomes key — the second is cheaper and covers the case that
  matters, since somebody editing a scheme comes back to the window to look.
- **Rebuild what is showing.** The scheme list in settings, and the window
  itself if the scheme being edited is the one in use. The second is what makes
  this worth doing at all: editing a colour and seeing it land is the whole
  point of the colours being in a file.

**Worth deciding:** whether a file that fails to parse while being edited
should say so on screen rather than only in `~/Library/Logs/Abydos/schemes.log`.
Half-written JSON is the normal state of a file somebody is typing into, so
this would be a message that appears and clears constantly — probably a line in
the settings page rather than anything modal, and probably only for the scheme
that is selected.

---

Its number is where it sits in the queue, not what it is worth doing next.
