# Find the manifest wherever it is, and say why a search found nothing

`c5cd642d5` · 2026-08-01

Symbol search was empty in a Go project, and so were go-to-definition and
everything else the server provides. The project keeps its module in `app/`,
as Go repositories commonly do, and servers were only ever offered the
project root — pointed at a directory with no go.mod in it, gopls answers
nothing and explains nothing.

Manifests are now looked for a couple of levels down, skipping vendored
copies, and the server is rooted where the manifest actually is. The same
fault would have hit any repository with `backend/Cargo.toml` or
`web/package.json`.

Servers also start when a project opens rather than when a file of their
language is first opened, so asking for a symbol immediately after opening a
project works. Only for languages the project evidently uses: the JSON
server names no marker files, fits every project on earth, and — being
uninstalled here — was drowning out the language actually in use with its
own complaint.

An empty list now says why: no server for this language and how to install
it, nothing typed yet, or genuinely nothing matching. "Nothing here" and
"nothing is running" looked identical, and one of them is fixable.

Escape closes the palette, and so does clicking away — a search field
swallows escape as "stop editing", so the panel has to take it.

Right-click in the editor for Go to Definition and Find Usages. Usages come
from the server rather than a text search, so they tell a `Close` on one type
from a `Close` on another, and are listed by file with the line each is on. A
single result is not a list; it is the place to go.

Verified against gopls on a real project: 100 symbols for "config", three
usages of a function with their lines, and a jump from a call on line 257 to
its declaration on line 25.
