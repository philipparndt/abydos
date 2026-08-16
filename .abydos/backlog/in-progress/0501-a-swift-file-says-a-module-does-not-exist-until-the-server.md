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

## What the server sends while preparing

Measured, not reasoned about. The probe drives `sourcekit-lsp` over stdio against
a package depending on Cadova — eighteen targets, most of them C++ — with its
build directory deleted, and prints every message the server sends with the time
it arrived. It was run twice, because **the answer depends on what the client
claims**, and one of the two answers is the one this app gets today.

Four other agents were building on this machine throughout, so the durations are
longer than the item's original 2 s / 40 s. The shape is identical.

### As the client asks today — no `window.workDoneProgress`

    t+  1.7s  diagnostics: 0
    t+ 12.0s  logMessage [3] Preparing Clipper2
    t+ 13.1s  diagnostics: 1 — No such module 'Cadova'
    t+ 12.0 … 56.3s  logMessage [3] Preparing <target>, eighteen of them, in
              dependency order: Clipper2, oneTBB, pugixml, Bridge, ManifoldCPP,
              Miniz, freetype, ManifoldBridge, Nodal, Zip, harfbuzz, Apus,
              Manifold3D, Pelagos, ThreeMF, Cadova, spike
    t+ 70.4s  diagnostics: 0

and **that is the whole of it**: no `$/progress`, no
`window/workDoneProgress/create`, no `window/showMessage`. Preparation is
visible only as prose in the log, at **level 3, info** — which matters, because
`LanguageService.serverSaid` only calls `ServerHealth.said` and posts a toast at
level 1. So a cold start today produces no toast and no health state, and
anything built here is purely additive rather than a correction.

The log line is also a poor thing to build on. `Preparing <target>` says a target
started and never says one finished; the finish is a separate
`Finished with exit code 0` that is also printed for every `Indexing <path>`
subprocess, hundreds of them, so pairing them up means counting strings. And
`Preparing` is `sourcekit-lsp`'s own word.

### With `window.workDoneProgress` advertised

Everything above, and in addition, from the same run:

    t+  1.7s  window/workDoneProgress/create  token 'indexing.<uuid>'
    t+  1.7s  window/workDoneProgress/create  token 'package-reloading.<uuid>'
    t+  1.7s  $/progress  indexing        begin  {"title": "Indexing",
                          "message": "Determining files", "percentage": 0}
    t+  1.7s  $/progress  package-reloading begin {"title": "SourceKit-LSP:
                          Reloading Package"}
    t+ 14.0s  $/progress  package-reloading end
    t+ 15.5s  diagnostics: 1 — No such module 'Cadova'
              … about 500 × report, "n / 649", with a percentage
    t+ 75.3s  diagnostics: 0
    t+ 75.4s  $/progress  indexing        end

**The `indexing` token brackets the false error almost exactly**: it begins 13.8 s
before the diagnostic appears and ends 0.1 s after it clears. That is the seam.
It is the protocol's own, it has an explicit end, and its title is the server's.

### Second open, the same package, nothing deleted

    t+  1.7s  $/progress  indexing  begin
    t+  2.4s  diagnostics: 0
    t+  2.9s  $/progress  indexing  end

No `Preparing` line at all and no false error, which is the item's 2.2 s figure
again. Note the number that decides where this is shown: **a warm start is still
1.2 s of "preparing"**.

The probe is
`scratchpad/lspprobe501.py`; the runs are `probe501-cold.log` (advertised),
`probe501-cold-nowdp.log` (as the app asks today) and `probe501-warm.log`.

## The decision: explain, and suppress nothing

**Explain.** The chip beside the caret says `sourcekit-lsp — preparing` while the
server is preparing, and its tool tip says the sentence. Nothing is held back:
the false error is still on screen, and what changes is that the window it lives
in has a name.

Three reasons, in the order they decided it.

- **Suppression cannot tell the two cases apart, and that is the whole
  complaint.** A dependency that genuinely is not there and one that has not been
  built yet publish the identical diagnostic; the only thing that separates them
  is time, and holding the message back for as long as preparation takes means
  the honest case is silent for a minute and then shouts. Worse, suppression is
  all-or-nothing at the wrong granularity: the diagnostics arriving at 13 s are
  not all false. A misplaced brace in the file being edited is real, useful, and
  reported in the same batch. Holding the batch throws the true ones away with
  the false ones, and holding only the false ones means matching
  `No such module` — one compiler's wording, in one language.
- **The chip is already on screen, so explaining moves nothing.** During
  preparation the server is running, so `LanguageService.footer` already returns
  `.answering` and the bar already draws `sourcekit-lsp`. Saying preparation is
  happening is one word changing in a chip that is there either way: no new
  furniture, nothing appearing, no layout shift, and nothing to dismiss.
- **The seam exists and the alternative's does not.** `LanguageServerFooter.State`
  is an enum of waits whose doc comment already reserves room for another case,
  and `arrivalSentence` is written in one place and read in two. Suppression has
  no seam at all — `client.onDiagnostics` writes straight into the table — so it
  would be new machinery for the weaker answer.

**Not the strip above the file.** It was the other candidate and it is measured
out: a warm start is 1.2 s of preparation, so a banner would appear and vanish
inside a second and a half on *every* project open, and the strip pushes the file
down when it appears — the text would jump twice for nothing. The strip is also
for what is wrong or missing, and a server that is preparing is neither; it is
running, and it will answer.

## Estimate

2026-08-16 13:46 — about two hours left

## Steps

- [x] Find out what the server sends while preparing — log messages, progress,
      or nothing — and write the answer here
- [x] Decide between suppressing and explaining, and write down which and why
- [x] A value in the engine that reads `$/progress` and says whether the server
      is still preparing, with a test
- [ ] Ask for `window.workDoneProgress`, and read `$/progress` in `LSPClient`
- [ ] The footer's chip says it, and the tool tip says the sentence
- [ ] Do it, for a file whose dependencies have not been built yet
- [ ] Watched: open a Swift package with a clean `.build`, and see what the
      first thirty seconds look like now
- [ ] Say whether this is Swift-only, and why that is or is not right
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
