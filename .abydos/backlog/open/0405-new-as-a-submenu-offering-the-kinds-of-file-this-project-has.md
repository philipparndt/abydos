# 405. "New" as a submenu, offering the kinds of file this project has

The folder context menu offers `New File…` and `New Folder…` side by side, and
`New File…` asks for a whole name — extension included, typed out every time.
In a project where nearly every new file is one of two or three kinds, that is
the same few characters typed again and again, and getting them wrong is how a
file ends up unhighlighted and unrecognised.

One `New` item with a submenu instead:

    New  ▸  File…
            Folder…
            ────────
            TypeScript (.ts)
            TSX (.tsx)
            …up to five

The five are the kinds of file *this* project is made of, worked out from the
project, not from a list in the source. Opening `~/dev/3d/other/kamado` should
offer `.scad` and `.md`; opening this one should offer `.swift` and `.md`.

`File…` and `Folder…` keep exactly today's behaviour, so nothing that works now
stops working — the submenu is a shortcut past the extension, not a new way of
creating things.

## Where it is

All of it is in `ProjectNavigatorViewController`: `makeContextMenu` builds the
flat menu, `contextNewFile` and `contextNewFolder` are the actions,
`contextParentDirectory` decides where the entry lands (beside the clicked
file, or inside the clicked folder), and `askForName` puts up the prompt and
runs `EntryName.problem` over the answer. A typed entry is `contextNewFile`
with the extension already known: still prompt for a name, still validate it,
still create intermediate directories, but append `.ts` if what was typed does
not already end in it. There is no File-menu equivalent to keep in step — the
context menu is the only place this exists.

## Choosing the five

Count what is there. `ProjectSearch.collectFiles()` already walks the project
with `Settings.shared.excludedDirectories` and `.git` pruned, which is the
walker to reuse — a second one would disagree with the first the day somebody
adds `target/` to the settings. Group by extension, most files first, take
five.

The counting is the easy half; the ruling-out is the half worth thinking about,
because a naive count of `kamado` puts `.3mf` and `.stl` near the top and both
are wrong. They are output, and neither can be edited — `FilePreview
.hasReadableSource` is the app's existing answer to "is this even text", and it
already names those two. Also to drop:

- **Pictures.** `FilePreview.kind(for:) == .image` covers them, `.svg` aside.
- **Files nobody creates by hand**: lock files, `package-lock.json`,
  `Cargo.lock`, minified bundles. A "created once, generated after" list is
  short and is better written down than inferred.
- **Extensions with no language.** `LanguageRegistry.languageId(for:)` says
  whether the editor knows a kind at all. Careful with this as a filter rather
  than a tiebreak: it would also drop `.txt` and `.env`, which are fine things
  to create.

Fewer than five is a normal answer, and an empty project is `File…` and
`Folder…` with no separator and nothing under it. Do not pad the list with
defaults the project does not use — a `.js` offered in a project with no
JavaScript in it is worse than an absent shortcut, because it invites a file
that does not belong.

## Left to decide

- **Titles.** `TypeScript (.ts)` reads better than a bare `.ts` and takes more
  width; `LanguageRegistry.displayName(for:)` already has the names.
- **When to count.** Once when the project opens is cheap and can go stale —
  the first file of a new kind will not appear until the project is reopened.
  Recounting on every right-click is honest and walks the tree while a menu is
  waiting to be drawn. Once per project, refreshed on the same filesystem
  events the navigator already listens to, is probably the answer.
- **Content.** Empty file, as today. Stub content per kind is a separate task
  and a much larger one — a `.tsx` template is an opinion about the project.

---

Previously numbered 394.
