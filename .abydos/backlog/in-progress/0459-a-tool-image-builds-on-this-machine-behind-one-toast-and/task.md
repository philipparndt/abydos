# 459. A tool image builds on this machine behind one toast and silence

Reported from use: choosing to build a language server's image here — 0434's
route, and 0457's kmp-lsp is the first one anybody would pick it for — shows one
toast and then nothing at all while the build runs.

0457 measured that build cold at **164 seconds**. `openscad-lsp` and kmp-lsp are
both Rust: a compiler, a registry fetch, and minutes. From the outside, minutes
of silence after a toast is indistinguishable from a feature that did not work,
which is the sentence already written above the `progress` closure in
`LanguageService`:

    // A pull with nothing on screen is indistinguishable from a
    // feature that does not work.

That comment is about a *pull*, and a pull is seconds. A build is minutes and got
the same treatment.

## What is actually missing, and it is one argument

`ContainerImageStore.ensure` already takes both halves:

    progress: (@Sendable (String) -> Void)? = nil,     // one sentence before it starts
    onOutput: (@Sendable (String) -> Void)? = nil      // the build's own output, as it arrives

`LanguageService` passes `progress` and **not** `onOutput`. So the sentence
arrives and the four minutes of `docker build` go nowhere. `ProcessPipes.drain`
grew `onOutput` for exactly this and says so in its own note — "a `docker build`
that takes four minutes is four minutes of nothing at all if its output only
appears at the end".

## The devcontainer path already solved this

`DevContainers` passes `onOutput:` into the build and the output lands in
`PreparingTerminal` — a tab that opens at once, has the work written into it, and
then *becomes* the shell, keeping the scrollback. 0444 added the same for the
language-server path when a *devcontainer* comes up, deliberately not taking the
keyboard, opening the panel only if the start is still going after three seconds,
and taking its tab away again if nobody could have watched it.

**All of that applies unchanged to a tool image build.** This item is mostly
routing an existing pane at an existing stream, and the decisions 0444 already
made — no keyboard, open late, tidy up after a fast one — should be taken rather
than made again.

## Worth deciding

- **Whether every image build gets a pane, or only a slow one.** A pull of a
  cached image is instant and a pane for it is noise. 0444's three-second rule is
  the precedent and probably the answer.
- **Where a failed build's output goes.** Today a failure is a toast with a
  reason, and `ToolImageRecipes` has a four-way explanation — runtime down, no
  network, registry refused, no disk. With a pane, the pane *is* the error and
  the toast should point at it rather than try to summarise a hundred lines of
  compiler output. Same decision 0444 recorded.
- **The other three callers.** `PlantUMLPreviewView`, `DiagramExport` and
  `DevContainers` all call `ensure`. The first two pull rather than build today,
  but a recipe can be written for anything, so whatever this does should not be
  wired only into `LanguageService`.

## Ruled out

Nothing yet — written before the work.

Worth knowing rather than rediscovering: the build output already crosses the
process boundary correctly. `ProcessPipes.drain` reads both pipes on threads of
their own precisely so a chatty build cannot deadlock against a full pipe, and
`drainText` decodes a piece at a time, which is why a multi-byte character split
across two reads comes back as a replacement character in the piece and not in
the whole.

## Estimate

2026-08-11 08:36 — about three hours left — the wiring is small, the cold build to watch is 164 s and the app has to be driven

## Steps

- [x] `LanguageService` passes `onOutput` as well as `progress`
- [ ] The output lands in a pane, on 0444's terms — no keyboard, opened only if
      the work is still going after three seconds, and its tab taken away if
      nobody could have watched it
- [ ] A failed build leaves its output where somebody can read it, and the toast
      points at the pane rather than summarising the compiler
- [x] The other callers of `ensure` get the same treatment, not just this one
- [ ] A pane that is only ever a report is not written into `.abydos/session.json`
      — found on the way, and the same fault 0444 fixed for the devcontainer tab
- [ ] Tests the kit can reach: the name test that says build or fetch, and a real
      build proving the output arrives while it runs rather than at the end
- [ ] Driven with a recipe that really builds — `ABYDOS_BUILD_TOOL_IMAGES=1` and
      a cold cache, which 0457 measured at 164 s
- [ ] Write down here what was ruled out on the way
- [ ] `spec/tool-images.md` says what the project now does
