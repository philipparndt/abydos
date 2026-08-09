# 414. A scheme dropped into the folder waits for the next launch

Schemes are files now (0402), and `~/.config/abydos/schemes` is where somebody
keeps their own. The folder was read once at startup, so a file written while
the app was running was not there until it was restarted — and the person
writing it is, by definition, sitting in front of the app trying colours out.

`SchemeLibrary.reload()` existed and did the right thing. What was missing was
somebody calling it and something noticing afterwards.

## Decided, and done

**Two small buttons beside the theme selector: a reload, and a reveal.** This
does not happen often enough to watch the folder for — a `DispatchSource` on a
directory, to catch something somebody does a handful of times in a year, is
machinery that has to be right for ever in exchange for saving one click.

- **Reload** — `arrow.triangle.2.circlepath`. Three things, and it is the
  middle one that this entry existed for: re-read the library, rebuild the
  settings rows so a new scheme appears in the list, and take the palette again
  so an edited colour lands on the window already open. `reload()` on its own
  repopulates the library and leaves the page exactly as it was, which looks
  like it worked and is worse than not offering it.
- **Reveal** — opens the folder, and makes it first if it is not there.
  Somebody who has never written a scheme has no folder, and a button that
  opens nothing is a bug report.

**A third fault was underneath, and would have made the button a lie.**
`Theme.apply()` decided whether anything had changed by comparing the scheme's
*name* — right for choosing a different theme, wrong for this: a scheme keeps
its name when its file is edited, so the one case the reload button exists for
was the one case that repainted nothing. It compares palettes as well now.

**The parse-failure question is answered by the button.** A file that will not
read is said plainly on the reload — named, with the key that is missing — as a
toast beside the button just pressed. That was the objection to saying it at
all: half-written JSON is the normal state of a file somebody is typing into,
so a watcher would have flashed a message constantly. A reload is a moment they
chose, so there is nothing to flash.

Two rows carry it: `Row.choiceWithActions`, rendered by both the window and the
in-editor page, and `.abydosSettingsRowsChanged` — kept apart from
`.abydosSettingsChanged` because rebuilding a page on every toggle would take
the focus out of whatever somebody was in the middle of.

---

Its number is where it sits in the queue, not what it is worth doing next.
