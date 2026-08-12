# Abydos 0.2.0

798 commits since 0.1.0. The theme of the release is that a project's tools come
with the project: language servers, diagram renderers and whole development
containers run from images rather than from whatever happens to be installed on
the machine — and that the editor now *changes* code through a language server
rather than only asking it questions.

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
not something the app can know. Written beside the source, it replaces only
pictures the app drew, refuses a file it did not, and reports the line a broken
diagram failed on rather than writing a picture of the error.

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

**Every external tool can run from a container**, with a recipe for each shipped in
the app: gopls, pyright, clangd, jdtls, kmp-lsp, openscad-lsp,
typescript-language-server, rust-analyzer. A project names an image, or asks for one
to be built here — and a build is now something you can watch, in a pane, rather
than one toast and then silence for the couple of minutes it takes.

**Choosing where a tool comes from changes something.** Picking an image for a
server that had already failed used to write the preference correctly and do
nothing at all, because what was remembered about the failure was remembered under
conditions that had just changed.

**Leftover containers are swept from every runtime installed**, not only the
preferred one. On a machine with a Docker CLI whose daemon is stopped, the sweep was
asking Docker, reading "listing did not succeed" as "nothing to remove", and never
looking in the runtime everything was actually in.

**Every devcontainer in a project is offered**, in the `+` chevron and in the menu
bar, and the titlebar's pill says which one is active.

## Language servers

**A project chooses which server answers for a language.** Two Java servers is
the case that forced it: jdtls understands the whole language and, measured on a
143-bundle project, was still silent at 601 seconds where kmp-lsp answered in
2.6. So `.abydos/tools.json` or Settings ▸ Tools names the one this project
wants, and the choice takes effect at once rather than at the next launch.

**A project can name the executable, not only the server.** Every toolchain
manager puts a proxy on the `PATH`, and a proxy resolves through the project —
which is how a Rust project pinned to a custom channel ended up unreadable by a
`rust-analyzer` that was sitting right there. A path in `.abydos/tools.json`, or
in Settings, is taken as written, and `initializationOptions` merge over the
built-in table so a server can be told things it could not be told before.

**The footer says which server is answering, and from where.** Beside the caret's
position: the name alone for the copy on this machine, the name with the
container mark and the image for a server in one, the mark alone inside the
project's devcontainer — because the container is a fact about the window and the
titlebar already names it. A server on its way says which wait it is in:
fetching, building or starting. Nothing at all for a language with no server,
which is most files in most projects. Clicking it opens the list of what is
running.

**A server that started and cannot read the project says so.** It used to be
invisible: the strip above the file went away the moment the process was up, so a
project the server could not make sense of looked exactly like one where
everything worked, until you opened the outline and found it empty. Now the
server's own words are on offer behind a button, and none of the three sentences
claims a crash — two of them say the server is running, and all three name the
project rather than the server.

**A toolchain a project pins is read before anything starts.** A
`rust-toolchain.toml` naming a channel no image can carry is answered with what
*would* read the project, rather than with a container that starts, answers the
handshake and then refuses every question about every file.

### Changing code, not only asking about it

**Rename, through the server.** ⇧F6 or Rename… on the code menu, typed in place
over the symbol — the navigator's row rename one layer in. It applies across open
buffers and closed files alike, as **one** undo: on the corpus, a rename that
touched 62 files and made 203 edits, applied and undone in one step. Nothing is
written until every file has been checked, a write that fails anyway is put back,
and a rollback that cannot finish names every file on both sides.

Two things that came out of building it. jdtls answers with **both** shapes and
the old one is empty — a `changes` map of zero files beside `documentChanges` of
thirty-two — so a client reading the wrong half applies nothing and reports
success. And a server can advertise rename, agree there is something to rename,
and then decline; when that happens the app now says *which* server declined,
which is the only thing distinguishing it from a caret on a comma.

**Java debugging no longer depends on which server edits.** Choosing the fast
server used to cost the debugger entirely, because the debug adapter is an
Eclipse bundle living inside jdtls. Measured, the adapter is listening long
before completion is: 36.9 s against a project Sirius takes minutes to answer
about. So a jdtls is started for the debugger alone, on the first Debug, and it
answers nothing about files — enforced rather than described.

**Find Usages is a list you work through.** It arrives docked in the bottom
panel beside search, with the keyboard in it: ↓ moves and previews, ⏎ takes you
into the editor, ␣ marks a row done. Two hundred rows under a held ↓ opens one
tab and tells the server seven times, not two hundred.

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

**⌘/ comments out the lines a selection touches**, and takes the comment off when
pressed again. At the shallowest indent the block shares, never at column zero, so
the shape of the code survives it; blank lines stay blank and do not flip the
toggle; and uncommenting removes exactly what commenting inserted, space or no
space. It knows 28 languages, which is more than the app has grammars for, and a
language with no line comment — CSS, HTML, Markdown, JSON — says so rather than
mangling itself with a `/* */` that cannot nest.

**⌘Z undoes what the tree does to a file** — creating, renaming, moving, copying
and trashing, each as one step.

**A new file is named on its row**, in the tree, sharing rename's machinery rather
than opening a dialog. Files and folders move and copy by drag, and a copy into the
folder it came from becomes `main-1.py` rather than a refusal.

**Search results are a checklist.** Rows can be selected several at a time and
marked done with ␣, which strikes them through and leaves them where they are — a
list that removed rows as you ticked them would move everything under the pointer
on every press. `✓` hides what is finished.

**A `.scad` opens with the model beside it**, which is what a `.scad` is for.
Measured at about 340 ms for the first render on a busy machine — cheaper than the
PlantUML split two cases above it, which starts a JVM. A directory walked with the
arrow keys renders nothing until you stop on a row.

**A go3mf recipe opens in the viewer it describes.** A `.yaml` naming an `output:`
and `objects:` is offered to the 3D viewer; every other YAML is not, which is
decided by reading the head of the one file you right-clicked rather than by
extension. It needs GoSTL 0.22.0, which stopped writing its build into the project
it was looking at.

**The commit view is the tree the project is**, with folders that stage everything
under them.

**A tab comes back the way it was being shown** — source, preview or split, divider
and all — when you switch projects and return.

## Git

**A repository with no commits has a branch.** `git init` and nothing committed left
the titlebar blank, because the question being asked resolves a commit before
naming it. Three states are distinguished now — a branch, an unborn branch, a
detached HEAD — and the branch of an empty repository is shown dimmed, with *"On
main — no commits yet"* on the tooltip. Amend is disabled instead of failing, and
the branch menu opens instead of not appearing.

## The backlog

Abydos keeps its own backlog as files beside the project, and this release ships the
tool and the pane that read it. An item is a card; a card knows the worktree an
agent is working it in and can reveal it; ticked steps and an estimate show on the
card while the work is somewhere else. `abydos-backlog` — installed with the app —
files, starts and finishes items, and folds each item's own spec delta into a
project spec that has to stay true.

## The model viewer

GoSTL runs in a tab rather than as a second program, pinned to a published version
rather than a directory. This release moves that pin to **0.22.0**, which fixes two
things found from here: a recipe used to be built *over* the project it was
describing, because `go3mf` ignores the output path it is given whenever the recipe
names one; and a failed load drew a lit test cube, which looks like an answer. A
failure now draws nothing and keeps its message.

## Terminal

**Ligatures survive a tmux pane border.** They were being switched off for every
line a border crossed, which looked like they depended on which pane had focus.

`abydos-icat` fits a picture to its **pane** rather than to the whole tmux
window, and says plainly when the terminal cannot draw pictures at all instead
of writing fourteen kilobytes of escape sequences at it.

**A command that finishes before anything reads it keeps its output.** A macOS pty
offers unread bytes for exactly 600 ms after the child exits and then discards them
— Linux keeps them for the reader — so a `/bin/echo`, a `git status`, `abydos-icat`
or a container build's first lines could be lost outright rather than late. They
are not any more, and everything the app runs through a pty goes through the one
fix.

**A picture placed where there is not room for it makes the room.** `kitty icat` on
a nearly full screen drew for one frame and was then erased by the next prompt,
leaving the gap where it had been — because the cursor advance clamped at the last
row and the picture's rows were left below the bottom of the screen. Four runs in a
row now draw four pictures.

**A pane tells the truth about how large its cells are**, which is what `icat` uses
to decide how many of them a picture needs; a window not yet on a screen was
reporting a scale of zero, and a cell of no pixels is how a terminal says it cannot
show pictures at all.

**libghostty-vt is available as the terminal engine, off by default**, behind a
setting in the shape the GPU renderer already has. Ghostty's parser is 17× faster
on plain text; its kitty graphics covers the protocol used outside tmux and half of
the one used inside it, and it draws tmux's rename prompt a row too high in the
configuration this app runs. So both engines are here, the existing one is
untouched, and which one drew a pane is printed where a bug report can carry it.

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

`make warnings` reports every warning in this repository's own code and nothing from
anybody else's — 67 seconds on a quiet machine, and the Swift half is at zero. It
greps for a warning rather than for a path, which is how three of them had stayed
invisible: a warning from inside a macro expansion carries no file name.

`make timing` is where a timing assertion lives now, run serially. `make test` still
measures and prints, with the load it measured under, and asserts nothing about the
clock — because the suite's own parallelism puts this machine at four runnable
threads per core, and the same warm render that costs 0.014 s alone costs 0.6 s
there. A budget that sits between those two numbers is a coin, not a check.

The corpus harness drives real projects — 500 bundles of Eclipse Platform — and a
stall log names its own suspects, which is how a filesystem event walking 45,772
files per keystroke was found: 667,907 ms down to 10,779.
