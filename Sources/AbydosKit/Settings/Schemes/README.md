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

### The exceptions

Three keys may be left out, and each has a *stated* derivation rather than a
silent default: it says what you get, and what you get is deliberately mild —
`midway` is never louder than the louder of the two colours it sits between.

They are exempt because they arrived late. Schemes were already files people
keep in a dotfiles repository, and requiring one would have refused every one of
them for having been written before it existed. State them anyway if you can:
the derivation is a floor for a file nobody has looked at, not a
recommendation. They are listed in `SchemeRole.optional`.

#### `app.selectionBackgroundInactive`

Selected text in an editor that has not got the keyboard. Absent, it is
**halfway between `selectionInactive` and `selectionBackground`** — halfway
between the gray a tree row goes when the keyboard is elsewhere and the colour
selected code is drawn in when it is not.

It exists because a row and a run of text want different amounts of lift from
the same background: a row is a band the width of the pane with an edge above
and below, and code is a ragged shape mostly covered by the glyphs on top of it.
`selectionInactive` was used for both until somebody selected a line of
`Package.swift`, put the keyboard in the terminal, and could not see it. Judge
it the same way — a real file, both lightnesses — and keep it below
`selectionBackground`, or an unfocused selection will shout over a focused one.

#### `app.searchMatchCurrentBackground` and `app.searchMatchBackground`

The find-in-file highlights: the match ⌘G is on, and every other match on the
screen. Absent, the current one is **halfway between `selectionBackground` and
`caret`** — the caret being the one colour a scheme guarantees can be seen
against its own editor at a glance, which is what a current match has to be —
and the others are halfway again back towards `selectionBackground`, so a
derived scheme cannot end up with the matches nobody is reading louder than the
one they are.

**Judge the pair together, and in that order.** These two were hardcoded in the
view until 0536 — one amber, one brown, both chosen against a dark warm ground —
so every light scheme drew its find highlights in somebody else's dark colours.
The rule the shipped schemes are checked against, in `SchemeTests`, is that the
current match has more contrast against `editorBackground` than the other
matches *and* than either selection colour, because the current match is also
the selection and anything that can land on the same characters must not be able
to take the eye off it.

Both are backgrounds under live code, so check the text on them too: a current
match dark enough to be loud in a dark scheme will have light glyphs on it, and
one light enough to be loud in a light scheme will have dark ones.
