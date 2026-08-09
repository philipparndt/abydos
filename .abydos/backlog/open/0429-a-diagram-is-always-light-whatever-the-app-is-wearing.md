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

## What has to be decided

- **How the export asks.** `Export ▸ PNG ▸ Light / Dark` is three levels of
  menu; `Export ▸ PNG (Dark)` doubles the items; a setting makes it invisible at
  the moment of choosing. Whichever is chosen has to work from both places the
  export lives — the preview's own menu and the file's in the navigator.
- **What the exported files are called** if somebody wants both. `diagram.png`
  and `diagram-dark.png` is the obvious pair, and it has to fit
  `DiagramExport`'s existing rules — which replace only pictures this app drew
  and refuse a stranger's file. A second name means a second stamp to check.
- **Whether the preview redraws on a theme change.** The app can change theme
  while a diagram is open; 0423's `ScalingPage` is the precedent for a pane that
  has to be told, and the settings page got it wrong in exactly this way.

## Worth knowing before starting

The whole diagram surface moved this week: PlantUML renders SVG through a warm
container (0422), Mermaid renders in a `WKWebView` with no container at all
(0425), and both export through one `DiagramExport` with rules about what a
picture may overwrite. Three renderers, one export, one preview pane
(`DiagramPaneView`) — so this is one change in the pane and the export, and
three small ones in the renderers, rather than three separate features.

---

Its number is where it sits in the queue, not what it is worth doing next.
