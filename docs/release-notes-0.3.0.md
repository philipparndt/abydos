# Abydos 0.3.0

Three hundred and sixty-six commits since 0.2.1, and this time almost none of
them are the terminal. **The debugger now shows values beside the code that uses
them, language servers offer to fix what they complain about, and a search that
used to freeze the window for nine seconds no longer freezes it at all.**

## Debugging

**A stopped program shows its values at the ends of the lines that name them.**
No hovering, no panel to look away to: `count = 12` in grey where the line ends,
for the frame that is stopped, in the file that is stopped, and never below the
line execution reached — a value there is either left over from the last pass or
has not been assigned yet, and drawing it in the same grey as a true one would be
a lie.

Nothing is asked of the adapter to draw them. Scrolling a stopped file with a
value beside every line makes **no requests at all**, because evaluating an
expression runs the debugged program's own code — a Java getter, a Python
`__repr__`, a Go `String()` — and drawing a hint must not be able to change the
program you are debugging.

**A value with something inside it opens.** `mux = *net/http.ServeMux {…}` is a
door: click it and a window opens on the object, with the fields under it, each
expandable, fetched when you reach for one and not before. The window takes the
keyboard when it opens, walks with the arrows, resizes from its edges, and copies
— a value, a name, a name and value, or the whole tree as it stands. Stopping or
resuming takes it away, because a tree of values from a program that is running
again is worse than no tree.

The panel's variables tree learnt the same things: clicking it gives it the
keyboard, and expanding a row keeps the row you were standing on. Both trees now
draw a selected row in the scheme's colour, from one implementation, so they can
no longer come to disagree about what "selected" looks like.

**Stopping says so.** A session that ends now reports how it ended, including the
exit code.

## Language servers

**⌥⏎ asks what the server offers about the line you are on**: quick fixes for its
own diagnostics, refactorings, and whatever else it has — in its own words,
unsorted and unedited. Taking one resolves it if the server answered cheaply,
applies its edit through the same machinery a rename uses, and runs its command if
it carried one — after which the server may ask the editor to apply an edit of its
own, which it does, and answers honestly about whether it worked. `source.*`
actions have no cursor, so they live in Edit ▸ Source Actions… rather than in a
menu that opens where you are typing.

There is no mark in the gutter, and that was measured rather than preferred: asked
at every line of a real file, gopls answered something about **16 lines of 16** and
jdtls about **10 of 10**. An indicator meaning "there is something here" would be
on every row of every file.

**A server that says it is not ready is not believed at full volume.** Open a
Swift package with nothing built and `No such module 'Cadova'` used to sit in red
on line 1 while the model built and rendered in the pane beside it — measured at
thirteen seconds after the file opens, withdrawn a minute later once eighteen
targets had been prepared. The diagnostic is still there, still on its line, still
in the server's own words; it is drawn as a note rather than asserted as a fact
until the server says it is ready.

**A file is asked of the server that was told about it**, rather than of whichever
subproject the scope pill happens to be pointing at. And the Swift indexer now
builds and stands *outside* the project — it had been writing 1,424 files into a
checkout that was not its own.

Language servers also stopped eating the budget meant for tools. Twelve slots
existed for programs the app runs; every server took one for the session and never
gave it back, so a project of a few languages spent the lot before any tool ran and
the first Cadova build of the day was refused.

## The editor

**Copy where you are.** ⌘⇧C copies `Sources/App/Main.swift:42` — the shape a
terminal, an assistant and `abydos` all understand, and a selection copies as a
range. Edit ▸ Copy Permalink copies the forge's URL for the file at a commit, so
it stays right; it says, before you send it, if the commit is not on the remote yet
or if the file has changes that mean the line on the forge is not the line on
screen. ⌘⇧V follows either back — and a permalink lands on the line the *text* is
on now, saying so when that is not the line the link named.

**The caret steps over whole characters.** An accent written as two code points,
an emoji with a skin tone, a family: one press of → or ⌃F now crosses the whole
of it, and so do both deletes. `⌃A`, `⌃E`, `⌃K` and `⌃O` do what they do
everywhere else, and `⌥↑`/`⌥↓` move by line again.

**Find** highlights are measured along the row they are painted on, so a match
inside a soft-wrapped line is drawn where the characters actually are; the current
match is the loudest thing on the page and takes its colour from the scheme; a
pattern that does not compile says so; and a find belongs to the tab it searched
rather than following you to the next one.

**Tabs**: one that does not fit is reachable from a chevron that says how many are
hidden, and it comes back out of the menu when there is room. A cross closes the
tab under it. Files dropped on an editor open in the group they were dropped on.
The side buttons on a mouse go back and forward.

A selection in a view that has not got the keyboard is drawn in a colour of its
own rather than looking active, and a place the editor is sent to is on the screen
by the time the scrolling stops.

## Search and usages

**Typing one character into search used to leave the window dead for 9.38
seconds**, with a worst single stall of 7.03 — measured by the program's own stall
watch, which pings the main queue from a thread of its own. Four queries typed in
a row now log nothing at all. A list that is not the whole answer says so, instead
of printing `4268 in 500 files` and looking complete.

A results list has **four homes** — in place, beside the editor, in the panel, or
a window of its own — and one control that names them, remembered between runs.
Clicking a row puts the keyboard in the list, ↓ shows each result as you pass it,
⌫ ticks one off (and ⌘⌫ still never does), ⌘Z takes the last marking back, and
⇧⌘F lands in the query field wherever the list is sitting.

## What a project depends on

The project view has a **Dependencies** section, read from what is already on
disk without running a build tool: **npm, pnpm, yarn, Cargo, Maven, Gradle, Bazel
and Conan**, each package with where it came from and the files inside it. Where
the list cannot be complete it says which of the three tools produced it and what
is missing, rather than presenting a partial answer as the whole.

Files that belong to no project — a toolchain's own sources, a header from a
dependency — now have a row of their own instead of appearing nowhere. A directory
inside the project stays the project rather than being treated as a move
elsewhere, and the panel's panes follow the window when it changes project.

## Previews

A Swift file whose target uses Cadova **opens with the model beside it**, built and
rendered, re-rendered when you edit and not when you build. A picture zooms and
pans, and 100% means the size the file says it is. A preview no longer opens the
Finder behind your back, and a recipe naming a file outside the build directory is
**contained rather than refused** — the tool honours `-o` for a recipe from 0.16.6,
so the refusal only survives against one older than that, and says so.

A pane that cannot render says what happened in text you can read, which for one
fixture had been drawn into a view no points wide.

## Git and the terminal

Changes can be **thrown away from the changes pane's own menu**, a file or a
folder at a time, from the unstaged list only, and the confirmation says how much
it takes and which of it is deleted rather than restored.

A pane's program now gets **its own signals and its own pty**: `⌃C` in one pane
stopped being able to reach a program in another, and a child no longer inherits
a terminal that is not its.

A pane drawn by the other terminal engine wears a mark saying so, with the reason
on its tooltip — an experiment switched on in one pane is otherwise invisible the
next day.

## The board

The panel's board reads `openspec/changes` as well as a backlog, in **OpenSpec's
own states** — Writing, Ready, In progress, Complete, Archived — with each card
showing the fraction of its tasks that are done. A card hands over the command that
picks it up, and a card part-way through offers three sentences instead: archive it
as it is, complete it because you have verified it yourself, or carry on. A project
with neither record is offered buttons to make one, and the view notices when one
appears rather than needing to be closed and opened again.

## Also

`make test` now fails the run when a test fails — it had been reporting `tee`'s
exit code, so anything that checked the status rather than reading the output had
been told the suite was green for as long as the script existed.

A driven run leaves the machine alone: it writes its preferences to a throwaway
store rather than your real ones, restores no session and saves none, and opens
only the project it was given. Twenty-five of the app's own test verbs had been
writing real files, nine real preferences.
