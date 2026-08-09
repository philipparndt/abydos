# Abydos 0.2.0

243 since 0.1.0. The theme of the release is that a project's tools come 
with the project: language servers, diagram renderers and now whole development
containers run from images rather than from whatever happens to be installed on 
the machine.

## Diagrams

**Mermaid**, drawn by the app itself. No container, nothing to install: a
`.mmd` or `.mermaid` file gets a preview pane and exports beside itself. A
render takes about ten milliseconds. The alternative — the official
`mermaid-cli` image — was measured at 2.16 GB on disk and a second per render,
which is why it is not what shipped.

**A ```` ```mermaid ```` block in a Markdown file draws as the diagram**, in the
preview, where the block is — which is where most Mermaid actually lives. A
block that does not parse keeps its code and says which line of the file is
wrong, rather than leaving a hole in the page.

**draw.io**, in draw.io's own editor. A `.drawio` file opens with the shape
sidebar, the format panel and page tabs, and saves back to the file the app
still owns — compressed if it arrived compressed. Export writes every page.

**PlantUML** renders about fifty times faster: one container is kept warm
instead of starting a fresh one per diagram, which was two seconds each time.
Diagrams are now drawn as vector and are sharp on a Retina screen; they follow
the window's zoom, which they previously ignored.

**Diagrams follow the app's theme** — dark window, dark diagram, for all three
tools. A diagram that states its own look keeps it, and the pane says so rather
than leaving you to wonder: *"This diagram sets its own look (`!theme
reddress-darkblue`), so it is drawn that way rather than in the app's theme."*

**Export** from either the preview or the file's menu in the tree, as PNG or
SVG, and in **either theme** — `Export ▸ PNG (Dark)` writes `diagram-dark.png`
beside `diagram.png`, because which of a README, a wiki or a slide wants dark is
not something the app can know. Written beside the source. It replaces only pictures the app drew, refuses
a file it did not, and reports the line a broken diagram failed on rather than
writing a picture of the error.

## PDFs

A PDF opens in the editor: continuous scrolling, text selection, and ⌘F search
that jumps to the page. It follows the window's zoom like everything else.

## Containers and devcontainers

**A project can name its own devcontainer.** `.devcontainer/devcontainer.json`
is read — image or Dockerfile, workspace folder, user, environment, ports,
mounts — and the project opens in it, in the window it was already in. Files
stay on your machine, bind-mounted, so the tree, search and git keep working at
local speed; only the tools move inside. A file naming features or Docker
Compose is refused with a sentence saying which, rather than starting something
half-configured.

**The lifecycle commands run**, each at its own moment: `postCreateCommand` once
when the container is made, `postStartCommand` on every start, and the rest as
the specification says. A command that fails names the field it came from, its
exit status and the last line it wrote — and nothing after it runs.

**The terminal shows the container coming up.** The tab opens at once and holds
the pull, the build and each lifecycle command as they happen, then becomes the
shell in that container with all of it still in the scrollback. The panel's `+`
grows a chevron beside it offering a terminal in the devcontainer, the way the
run button does.

**Language servers run inside it**, so a project's toolchain is the container's
rather than the machine's, while every path they report is still named the way
this machine names it.

**Every container the app starts is named** `abydos-…` and removed when it is
done with, including containers left behind by a run that crashed. Before this,
they accumulated until the runtime wedged.

**Images are fetched before first use**, once however many panes ask, with the
name on screen while it happens and a failure that says which of four things
went wrong. An image that exists in the other runtime's store is now said to be
there instead of being reported as a wrong name.

## Editor and navigator

The navigator **selects more than one row**, renames in place, and has a **New**
submenu offering the kinds of file the project actually contains.

Keys follow the editor rather than the Finder: **Return opens** a file, **F2**
or **⌥Return** renames it, **⌘⌫** moves it to the trash.

**Settings are one page** with a tree, and Tools has a page per tool. The page
keeps the width it is dragged to, folds Tools away with the arrow keys, and
follows the zoom while it is open.

**Colour schemes are files.** Each ships as JSON, and your own go in
`~/.config/abydos/schemes`; a reload button beside the theme picker re-reads
them without a restart. A file missing a colour is refused by name rather than
half-applied.

## Terminal

**Ligatures survive a tmux pane border.** They were being switched off for every
line a border crossed, which looked like they depended on which pane had focus.

`abydos-icat` fits a picture to its **pane** rather than to the whole tmux
window, and says plainly when the terminal cannot draw pictures at all instead
of writing fourteen kilobytes of escape sequences at it.

## Everywhere

A **large zoom** is now the same interface, larger: the tree's icons, the
titlebar pill, toasts, the banner's buttons and the terminal's row grid all
scale. Above about 1.5× a system pop-up button cannot be drawn larger by
AppKit — that limit is documented rather than faked.

## For anybody working on Abydos

`make run` and `make open` build debug — 9 seconds rather than 98. `make build`
and `make install` still build release. A build takes four cores rather than
every one of them; say `JOBS=10` when a build is the only thing happening.

The performance suite measures processor time rather than wall clock, so it
stops failing because the machine was busy.

## Install

Download the DMG, open it and drag Abydos to Applications. The build is signed
with a Developer ID and notarised. Requires macOS 14 or newer.
