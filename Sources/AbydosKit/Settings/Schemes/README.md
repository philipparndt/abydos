# Schemes

One file per scheme. Two sections — `app` for the editor and its chrome,
`terminal` for the terminal — and every colour a light/dark pair, so a scheme is
one thing to read instead of four places in two Swift files.

The files here are the ones the app ships. Your own go in
`~/.config/abydos/schemes` (or `$XDG_CONFIG_HOME/abydos/schemes`), which is read
at every start: dropping a file in there is the whole of adding a scheme, and a
file there with the same `id` as one of these replaces it.

## The shape

```json
{
  "id": "nord",
  "title": "Nord",
  "order": 5,
  "about": "Why this palette is the way it is.",
  "app": {
    "windowBackground": { "light": "#F7F8FA", "dark": "#1A1C21" },
    "…": "one pair per role, all of them",
    "syntax": {
      "keyword": { "light": "#0033B3", "dark": "#D8926B" },
      "…": "one pair per kind, all of them"
    }
  },
  "terminal": {
    "background": { "light": "#F4F6FB", "dark": "#282935" },
    "foreground": { "light": "#24262B", "dark": "#FFFFFF" },
    "cursor":     { "light": "#3B3E45", "dark": "#C5C8C6" },
    "ansi": {
      "black": { "light": "#2B2D30", "dark": "#1D1F21" },
      "…": "all sixteen, by name"
    }
  }
}
```

- **`id`** is what the setting stores and what one scheme is known by. The
  filename is not it, so renaming a file does not make it a different scheme.
- **`title`** is what the settings window shows. Defaults to the id.
- **`order`** is where it sits in the list. A file that does not say goes after
  the ones that do, alphabetically — which is where a personal scheme lands
  unless it asks for a place.
- **`about`** is prose, ignored by the app. It is where the reasoning lives now
  that the colours are not next to a doc comment.
- **`stored`** — `{ "dark": …, "light": …, "system": … }` — overrides the values
  the setting holds for this scheme, which are otherwise `nord`, `nord-light`
  and `nord-system`. Only `blue.json` uses it, because its three were named
  `dark`, `light` and `system` before this app had a second palette.

Both sections are optional, but a file with neither is not a scheme. A scheme
with only `app` is a theme with no terminal palette of its own; one with only
`terminal` is a terminal palette that no theme list offers — `editor.json` is
that, and says `"follows": "editor"` instead of stating a background, foreground
and cursor, which makes the terminal wear whatever the editor is wearing.

Roles, syntax kinds and ANSI names are listed in `Scheme.swift` — `SchemeRole`,
`HighlightKind.schemeKey` and `SchemeAnsi`.

## A missing colour refuses the file

Every role, every syntax kind and all sixteen ANSI colours must be there, each
with both halves of its pair, each `#RRGGBB`. A file missing one is not loaded
at all: the reason names the key and the file, it goes to
`~/Library/Logs/Abydos/schemes.log`, and the scheme it would have replaced —
or the built-in one — stands.

The alternative was to fill the gap in from somewhere, and a theme applied
nine-tenths of the way is diagnosed by staring at a window and wondering. A
forgotten key and an unread file look exactly the same when the app inherits
silently; they look nothing alike when it refuses.
