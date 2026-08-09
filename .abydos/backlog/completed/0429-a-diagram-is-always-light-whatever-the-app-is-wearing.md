# 429. A diagram is always light, whatever the app is wearing

A PlantUML diagram in the preview is a white rectangle in a dark window. So is a
Mermaid one, and draw.io will be the same. The app has had themes since 0402
made every scheme a file, and the one surface that ignores them is the one
somebody stares at while writing a diagram.

Two separate wants, and they are not the same:

- **The preview should follow the app.** Dark theme, dark diagram.
- **An export should let somebody choose.** A picture written beside the file
  goes into a README, a wiki, a slide — and which of those wants dark is not
  something the app can know. So it is asked, not inferred.

## How each tool does it, and the third is a guess

- **Mermaid** is easy and already reachable: `mermaid.initialize({ theme: … })`
  takes `default`, `dark`, `forest`, `neutral`, `base`, and the page is ours —
  `Sources/AbydosKit/Preview/Mermaid.swift` builds it. Note the background is
  separate from the theme, and today the app deliberately paints white behind
  the SVG because CoreSVG ignores the CSS background; that code has to learn
  about this rather than fight it.
- **PlantUML** has `!theme <name>` and a large set of shipped themes, several of
  them dark. **Measure before designing**: whether the command line can impose
  one (`-theme`) or whether it has to be injected into the source, and what
  happens when the file already says `!theme` — because rewriting somebody's
  diagram to recolour it is not acceptable, and a diagram that names its own
  theme has chosen.
- **draw.io** has a dark mode in both viewer and editor, but it is not yet
  written, so this entry is a note to whoever does it rather than a measurement.
  0426 is where that work lives.

## Decided

**The file wins; the app's theme is the default.** A diagram that says `!theme`,
sets `skinparam backgroundColor`, or names a Mermaid theme in its own front
matter has been given a look on purpose, and recolouring it would overrule its
author — who may have chosen those colours precisely because of where the
picture ends up. A file that says nothing gets the app's theme, which is the
common case and the one this entry exists for.

Two things follow, and both are part of the work rather than afterthoughts.
Deciding *whether* a file states a theme is a question each renderer has to
answer about its own language, so it belongs beside that renderer and wants a
test — a diagram that sets only a background colour still counts as having
chosen. And when the file wins, that should be **visible** rather than
mysterious: somebody whose diagram stays light in a dark window must be able to
see that their own file asked for it, or they will report this bug again.

## What has to be decided — and what was

- **How the export asks.** `Export ▸ PNG ▸ Light / Dark` is three levels of
  menu; `Export ▸ PNG (Dark)` doubles the items; a setting makes it invisible at
  the moment of choosing. Whichever is chosen has to work from both places the
  export lives — the preview's own menu and the file's in the navigator.

  **Four items, all four qualified, the pair on screen first:** `PNG (Dark)`,
  `SVG (Dark)`, `PNG (Light)`, `SVG (Light)`. Not three levels, because that is
  a maze for something done often; not a setting, because the moment of choosing
  is the point — which of a README, a wiki and a slide wants dark is not
  something a preference set last month knows. Both pairs are qualified rather
  than only the odd one out: an unqualified `PNG` beside a `PNG (Light)` reads
  as "the normal one", and in a dark window the normal one is the dark one.
  Over a diagram that states its own look there is nothing to choose, so it
  falls back to the two items it always was. `DiagramExportMenu` builds the list
  once and both menus fill from it.

- **What the exported files are called** if somebody wants both. `diagram.png`
  and `diagram-dark.png` is the obvious pair, and it has to fit
  `DiagramExport`'s existing rules — which replace only pictures this app drew
  and refuse a stranger's file. A second name means a second stamp to check.

  **`diagram.png` and `diagram-dark.png`, and the name says what is in the
  picture.** Light keeps the name it has always had, so a README already
  pointing at it does not become a dark picture the day somebody switches theme,
  and a light re-export still replaces it. It composes with the numbering
  PlantUML's own file output uses: `diagram-dark.png`, `diagram_001-dark.png`.
  **A second name turned out not to be a second stamp** — `refusal` reads the
  *bytes* of whatever is already there (PlantUML's own marker, `DiagramStamp`'s,
  or draw.io's `mxfile` chunk) and never the name, so the dark file is protected
  and replaceable by exactly the same rules, with no new `DiagramStamp.Tool`
  case and nothing to keep in step. Tested.

- **Whether the preview redraws on a theme change.** The app can change theme
  while a diagram is open; 0423's `ScalingPage` is the precedent for a pane that
  has to be told, and the settings page got it wrong in exactly this way.

  **Yes, and it is a redraw rather than a repaint.** The zoom needs only a
  repaint because a drawing is scaled at draw time; a theme is a *different
  picture* and has to be asked for again. `DiagramPaneView` compares
  `Theme.current.name` against what the picture on screen was drawn for, so a
  settings change that was not a theme change costs nothing. draw.io is the
  exception and is *told* rather than redrawn — reloading its page would take
  its undo stack and anything unsaved with it.

## What each renderer came to

- **PlantUML** — `--dark-mode`, measured against `plantuml/plantuml:1.2026.6`
  before anything was designed. It exists, so does `--theme <name>`, and
  `--dark-mode` is the one that does not pick a palette for somebody out of the
  forty shipped. It paints a real `<rect fill="#1B1B1B">` into the drawing,
  which the light output does not — the light background is CSS on the root
  element, which CoreSVG ignores, and that is why the pane paints paper at all.
  **There is no way to ask for dark from inside a diagram**: no pragma (the
  whole `PragmaKey` list was read out of the jar), no skinparam, and `%is_dark()`
  can only read it. **And the kept-warm route cannot carry it**: `/plantuml/
  <format>/~h<hex>` is the source and nothing else — `?dark=true` is answered
  500 and there is no `/plantuml/dsvg/…`, both measured against a live server.
  So the flag goes on the command line for `-pipe` and on the container for the
  server, which is kept per image *and per theme*; nothing of anybody's source
  is rewritten, not even the copy sent to the renderer, and both routes draw the
  same picture. It costs at most one extra JVM for five minutes after somebody
  has drawn both ways.
- **Mermaid** — `mermaid.initialize({ theme })`, `default` and `dark`. The page
  keeps its whole options object and passes all of it every time, because
  `initialize` replaces rather than merges and a call carrying only a theme
  would quietly put `htmlLabels` back on. The background is separate, as the
  entry warned: Mermaid emits none, so the paper goes into the exported file as
  a rectangle over the `viewBox` and into the rasterising canvas as its fill —
  and only when this app chose the look.
- **draw.io** — **`mxUtils.preferDarkColor`, with `lightDarkColorSupported`
  staying off.** `EditorUi.setDarkMode` is the obvious thing to reach for and is
  a **no-op** here: its whole body is inside `mxUtils.lightDarkColorSupported &&
  (…)`, and that flag is off on purpose since 0426. draw.io's own SVG export
  shows the way round it — it sets exactly these two flags for a themed export —
  so 0426's lesson stands untouched and every colour is still written once, as
  itself. In the editor the two halves are separated: the chrome follows the app
  whatever the file says, and the shape colours follow it only when the document
  has stated no background of its own.

## How each language says it has chosen

Beside its own renderer, each with tests in `DiagramThemeTests`:

- `PlantUML.statedLook` — `!theme <name>`; `skinparam backgroundColor` in either
  spelling, including inside a `skinparam { … }` block; `BackgroundColor` inside
  a `<style>` block. Not a `skinparam` that colours one thing: an arrow tinted
  red is somebody colouring a thing, not choosing how the diagram is lit.
- `Mermaid.statedLook` — front matter `config: theme:` or `themeVariables:`, and
  the older `%%{init: {'theme': …}}%%` directive.
- `Drawio.statedLook` — `<mxGraphModel background="…">`, which is the one thing
  in the document that is a decision about how the whole picture is lit, and is
  exactly the value the renderer already paints.

When the file wins the pane says so in a line under the picture — "This diagram
sets its own look (`!theme reddress-darkblue`), so it is drawn that way rather
than in the app's theme" — and an export that was asked for the other theme says
the same thing in a notice. A caption rather than a toast, because a toast is
gone by the time anybody wonders.

## Left open

**Whether the paper could be the scheme's own colour rather than one neutral
dark.** It is `#1B1B1B` today for all three, and that is PlantUML's: its
`--dark-mode` paints that rectangle into the picture and there is no flag to
change it, so the other two are painted to match rather than the other way
about. Making the *pane* use `editorBackground` instead is one line — but the
paper is part of the picture, and an exported file must not carry somebody's
editor colours into a README, so the pane and the file would then disagree.
Reaching it properly means: Mermaid via `theme: 'base'` and `themeVariables`,
draw.io via the background already handed to `getSvg`, and PlantUML via a
generated `--config` file of `skinparam backgroundColor` (which exists, and
would mean a warm server per scheme rather than per theme). Worth its own entry
if it is wanted.

## Worth knowing before starting

The whole diagram surface moved this week: PlantUML renders SVG through a warm
container (0422), Mermaid renders in a `WKWebView` with no container at all
(0425), and both export through one `DiagramExport` with rules about what a
picture may overwrite. Three renderers, one export, one preview pane
(`DiagramPaneView`) — so this is one change in the pane and the export, and
three small ones in the renderers, rather than three separate features.

---

Its number is where it sits in the queue, not what it is worth doing next.
