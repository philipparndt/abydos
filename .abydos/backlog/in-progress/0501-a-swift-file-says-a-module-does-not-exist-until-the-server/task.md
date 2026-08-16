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

## What watching it found that reading it did not

The chip was written, built and opened on a cold package, and the screenshot at
t+22 s had something in it nobody had predicted: the strip above the file saying
**"sourcekit-lsp is running and says something is wrong with this project"**, and
a red toast saying **"sourcekit-lsp cannot read this project"**. Those are 0461's
sentences, and 0461 is about a server that will never answer. This one answered
thirty seconds later.

The cause is in `lsp.log`, and it is the same shape as the diagnostic:

    14:11:58 sourcekit-lsp says [error] 🟪🟩⬛️ Finished with signal 2 in 0.40s
    14:06:30 sourcekit-lsp says [error] ⬜️🟩⬜️ Finished with exit code 1 in 2.16s

Those are the *subprocesses of the server's own index build* — it starts one
`swift build` per target and one indexing process per file, and it reports the
ones that do not exit cleanly at **level 1**. `LanguageService.serverSaid` takes
level 1 as a report, and `ServerHealth` then only needs a question the server
could not answer to escalate that to "cannot read this project" — which is
exactly what hover and completion over an unbuilt module do for the whole of the
same minute. Both halves of `.cannotRead`, both of them false, both of them
caused by preparation.

**Checked rather than assumed**, and both directions were watched:

- *Before* (`watch-before.png`, the build at `cfb5ecf`): `No such module 'Cadova'`
  in red, footer `sourcekit-lsp`, indistinguishable from a healthy server. The
  toast and the strip appear in the same run a few seconds later.
- *After* (`watch-after.png`): the same red diagnostic, still not suppressed;
  footer `sourcekit-lsp — preparing`; **no strip and no toast**.

So the item grew a step. While a server is preparing, what it says at error level
does not reach `ServerHealth`, and an empty answer is not counted against it —
an answer *with* content still is, because that is the evidence that withdraws a
sentence and there is no case for holding good news back. Nothing is lost for
good: `said` keeps the first diagnosis and the state stays `.working`, so a
server that really cannot read the project says so again once it is ready and is
believed then.

## The first thirty seconds, before and after

Both are the same package with its index scratch directory deleted, opened by
the same driver, photographed at t+22 s: `images/watch-before.png` is the build
at `cfb5ecf`, `images/watch-after.png` the build with the change in.

| | before | after |
| --- | --- | --- |
| t+2 s | file drawn, no error | file drawn, no error |
| t+13 s | `No such module 'Cadova'`, red | `No such module 'Cadova'`, red — unchanged |
| footer, throughout | `sourcekit-lsp` | `sourcekit-lsp — preparing` |
| tool tip | "sourcekit-lsp is answering for Swift in this project, from …" | "sourcekit-lsp is building what this project depends on … may be about the build rather than about the code" |
| t+20 s | strip: *"sourcekit-lsp is running and says something is wrong with this project"*, and a red toast: *"sourcekit-lsp cannot read this project"* | nothing above the file, no toast |
| t+70 s | error clears, footer unchanged | error clears, footer back to `sourcekit-lsp` |

The one thing deliberately identical in both columns is the red on line 1. That
is the decision: nothing is hidden, and what changed is that the minute it lives
in now has a name.

## Not Swift-only, and nothing in it names Swift

The item asks whether fixing this for one language and calling it done would be
honest. It would not have been, and it turned out not to be necessary: **there is
no Swift in any of this.** The client asks for `window.workDoneProgress`, reads
`$/progress`, and the chip says the word for whichever server reported the work.
`sourcekit-lsp` is not mentioned in `WorkDoneProgress`, in `LSPClient`, or in
`LanguageServerFooter` except in a comment saying where the measurement came
from.

That was checked against the other two servers on this machine, cold, with the
same probe (`probe-others.py`, `probe-ra.log`, `probe-gopls.log`):

| server | tokens | titles | the wait |
| --- | --- | --- | --- |
| `sourcekit-lsp` | `indexing.<uuid>`, `package-reloading.<uuid>` | `Indexing`, `SourceKit-LSP: Reloading Package` | 1.7 → 75.4 s cold, 1.7 → 2.9 s warm |
| `rust-analyzer` | `rustAnalyzer/Fetching`, `…/Roots Scanned`, `…/Building CrateGraph`, `…/Loading proc-macros`, `…/cachePriming`, `rust-analyzer/flycheck/0` | `Fetching`, `Roots Scanned`, `Building CrateGraph`, `Loading proc-macros`, `Indexing`, `cargo check` | 0.2 → 8.7 s cold |
| `gopls` | `8906325497762287244` — a *number* | `Setting up workspace` | 0.1 → 0.8 s |

Three things came out of that table that reading one server would not have given:

- **`gopls` numbers its token.** The protocol allows a string or an integer and
  this is the first thing in the app to read a token at all, so the client
  flattens the two.
- **`rust-analyzer` closes each step before opening the next**, which is what
  broke the first rule and is written up above.
- **`rust-analyzer` reports `cargo check` after every save**, on
  `rust-analyzer/flycheck/0`. That is the flicker the once-per-server rule exists
  to prevent, and it is not hypothetical.

Whether the word is *useful* does vary by language, and that is a fact about the
languages rather than about the code: `gopls` prepares for 0.8 seconds and
nobody will ever read the chip, `rust-analyzer` for 8.7, and `sourcekit-lsp` for
over a minute on a package with C++ in it. A rule that fired only where it were
worth reading would need a threshold nobody can defend, and the honest version of
it — say what the server is doing, for as long as it is doing it — costs nothing
where the wait is short.

**jdtls is the one that is not covered**, and deliberately: it says how far it has
got over `language/status`, its own notification rather than the protocol's, which
`LSPClient.onStatus` already reads for the debugger's sake (0452). Routing that
into the same word was left alone — it is a second source for one sentence, and
the shape of a Java import is a wait *before* the handshake as much as after it,
which is a different problem from this one.

## Ruled out

- **Suppressing the diagnostic until preparation finishes.** The item's other
  option, and the argument against it is above under the decision: it cannot tell
  a missing dependency from an unbuilt one, which is the complaint rather than
  the fix, and it is all-or-nothing at the wrong granularity — a misplaced brace
  arrives in the same batch as the false `No such module`.
- **Matching `No such module` and holding only that.** One compiler's wording, in
  one language, and it would need a new one for every server the same shape.
  Ruled out with the point above rather than separately, but it is the version
  somebody will suggest, so: no.
- **The strip above the file.** Measured out rather than argued out. A *warm*
  start is 1.2 s of preparation, so the banner would appear and go inside a
  second and a half on every project open, and it pushes the file down when it
  appears — the text would jump twice for nothing. The chip is already drawn
  while this is happening, so there it is one word changing and nothing moving.
- **Reading `Preparing <target>` out of `window/logMessage`.** It is what the
  server sends today and it was the obvious route. It says a target *started* and
  never says one finished; the finish it does print — `Finished with exit code 0`
  — is shared with hundreds of indexing subprocesses, so pairing them up means
  counting strings; and `Preparing` is `sourcekit-lsp`'s own word, which would
  have made this Swift-only for no reason. `$/progress` has an explicit end and
  every server has it.
- **Treating an empty set of open tokens as the end of preparation.** Written,
  tested, and wrong — see above. It survives one server and fails the next, which
  is the argument for measuring more than one.
- **A progress bar, or a percentage.** `sourcekit-lsp` sends one — `n / 649`,
  with a percentage — and it was not used. The count is of *index* units and it
  reached 99% about five seconds before the diagnostics cleared, so as a
  prediction of the wait it would have been confidently wrong at the moment
  somebody was most likely to be looking at it. A word that is true beats a
  number that is nearly right.
- **A fifth state on `ServerHealth`.** Preparation is not a kind of ill health —
  the server is fine, and 0461's three sentences are all about a server that will
  not answer. What preparation needed from `ServerHealth` was the opposite: to be
  kept *out* of it, which is what the guard does.

## Estimate

2026-08-16 14:25 — about an hour left

## Steps

- [x] Find out what the server sends while preparing — log messages, progress,
      or nothing — and write the answer here
- [x] Decide between suppressing and explaining, and write down which and why
- [x] A value in the engine that reads `$/progress` and says whether the server
      is still preparing, with a test
- [x] Ask for `window.workDoneProgress`, and read `$/progress` in `LSPClient`
- [x] The footer's chip says it, and the tool tip says the sentence
- [x] Do it, for a file whose dependencies have not been built yet
- [x] Keep what a server says while it is preparing out of `ServerHealth` —
      found by watching, not by reading
- [x] Watched: open a Swift package with a clean `.build`, and see what the
      first thirty seconds look like now
- [x] An empty set of tokens is a question, not an answer — measured against
      rust-analyzer and gopls, not just sourcekit-lsp
- [x] Say whether this is Swift-only, and why that is or is not right
- [x] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
