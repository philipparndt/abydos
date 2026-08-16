# 501. A Swift file says a module does not exist until the server has prepared it

Open a Swift file in a package whose dependencies have not been built, and the
first thing the editor shows is an error that is not true:

    No such module 'Cadova'

Measured with `sourcekit-lsp` driven directly over stdio, on a package
depending on Cadova, dependencies resolved but not built:

    t+ ~2s   diagnostics: 1 — No such module 'Cadova'
             (the server then runs `swift build` to prepare the target)
    t+~40s   diagnostics: 0 — and hover and completion answer properly

On the second open, with the package already built: **clean at 2.2 seconds**,
no false error at any point. So this is a cold-start window, not a broken
setup, and it lasts as long as building the dependencies takes.

The answer is right in the end. What is wrong is that for the first half a
minute the file is covered in red for a reason that has nothing to do with the
code, and nothing says a build is happening — which is indistinguishable from a
genuinely missing dependency, and the natural response to it is to go and look
for a mistake that is not there.

## Not the same as 0461

0461 is *a server that started and cannot read the project* — a real failure,
said above the file. This is a server that is reading the project correctly and
has not finished yet. The distinction matters because the answer is probably
the opposite: 0461 makes something appear, and this should make something
**not** appear, or appear as progress rather than as an error.

0461 is completed and is not being reopened for this.

## Worth deciding

- **Suppress, or explain.** Holding "no such module" back until preparation has
  finished is the quiet answer and risks hiding a real one — a dependency that
  genuinely is not there looks identical until the build fails. Showing
  "preparing" instead is more honest and needs somewhere to show it. The footer
  already says which server is answering (0463), which is a candidate.
- **Whether the server says it is preparing.** It logs `Preparing <target>`
  over `window/logMessage`, and it may report work-done progress if the client
  advertises `window.workDoneProgress`. What it actually sends should be
  measured before anything is designed on top of it — this item's own numbers
  came from a probe, and the same probe can answer this.
- **Which languages this is about.** It was found in Swift, but any server that
  builds before it can answer has the shape. Fixing it for one language and
  calling it done would be worth saying out loud either way.

## Steps

- [ ] Find out what the server sends while preparing — log messages, progress,
      or nothing — and write the answer here
- [ ] Decide between suppressing and explaining, and write down which and why
- [ ] Do it, for a file whose dependencies have not been built yet
- [ ] Watched: open a Swift package with a clean `.build`, and see what the
      first thirty seconds look like now
- [ ] Say whether this is Swift-only, and why that is or is not right
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
