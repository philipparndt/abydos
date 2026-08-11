# 465. The build has eight warnings, two of which are the compiler being right

A clean build into a scratch path — which is the only way to see them, since an
incremental build only reports the files it recompiled — has **eight Swift
warnings**, seven in `Sources/` and one in `Tests/`. They have accumulated
quietly for the reason all warnings do: nobody sees them twice.

They are not the same kind of thing, and fixing them as one sweep of `_ =` and
`let` would miss the two that are the compiler telling the truth about a bug.

## The two that are real

**`Sources/AbydosApp/Editor/EditorViewController.swift:1229` — `'weak' ownership
of capture 'self' differs from implicitly-captured strong reference in outer
scope.** The text is decoded off the main queue and the result is sent back with
`[weak self]`:

    EditorViewController.languageTextQueue.async {
        let text = snapshot.string(in: 0..<snapshot.byteCount)
        DispatchQueue.main.async { [weak self] in

The outer closure has to capture `self` strongly to build the inner one, so the
`weak` buys nothing: the controller is held alive until the decode finishes
whatever happens. It is a delay rather than a leak, but the comment beneath it is
about a document that may have closed in the gap, and the capture was written to
make that safe. **Making the outer capture weak too is the fix, and it changes
behaviour** — which is why this is not a tidy-up.

**`Sources/AbydosKit/Support/ProcessPipes.swift:148` — converting non-Sendable
function value to `@Sendable (Data) -> Void` may introduce data races.** This is
the streaming path — `drain(onOutput:)`, which is what a container build's
progress lines come out of. The caller's closure is not `@Sendable` and is
being called from the reading queue anyway. Typing the parameter `@Sendable` and
letting that propagate to the callers is the honest fix; silencing it is not.

## The two that are errors in waiting

Both say *"this is an error in the Swift 6 language mode"*, and this package is
Swift 6 tools in Swift 5 language mode, so they are a bill that arrives later:

- `Sources/AbydosKit/Preview/MermaidRenderer.swift:72:35`
- `Sources/AbydosKit/Preview/DrawioRenderer.swift:53:34`

both: main actor-isolated static property `rasterScale` referenced from a
nonisolated context. The same property in the same shape twice, so one decision
answers both.

## The four that are tidying

- `Sources/AbydosKit/Preview/WebRenderer.swift:151` — no `async` operations occur
  within `await`
- `Sources/AbydosKit/LSP/Snippet.swift:38` — `var characters` never mutated
- `Sources/AbydosApp/Editor/EditorViewController.swift:2571` — result of
  `contextMenuTitlesForTesting(overTab:)` unused. It is called for its side
  effect and the comment beside it says so; `_ =` and keep the comment.
- `Tests/AbydosKitTests/DevContainerTests.swift:303` — result of `try?` unused

## Not in scope

- **`Sources/Grammars/TreeSitter{YAML,Python}Vendored/src/scanner.c`** —
  `-Wshorten-64-to-32` in vendored upstream C. Ours to carry, not to edit: a
  local fix is a diff against the grammar that has to be re-applied at every
  bump. If they are noise, the answer is a warning flag on those targets in
  `Package.swift`, and that is a decision of its own — say which was chosen.
- One build-system line, `missing creator for mutated node:
  …/GoSTL_GoSTL.bundle/Contents/MacOS`, which is SwiftPM and not this code.

## Worth deciding

**Whether the build should stay at zero afterwards, and how anybody would know.**
Eight warnings accumulated because nothing fails when one appears. A check that
the build is warning-free is the only thing that keeps this item from being filed
again in six months — but it has to be a check somebody can run and not a wall
that stops work, and vendored C means it cannot simply be `-warnings-as-errors`
across the package. Decide it here rather than leaving the sweep to rot.

## Steps

- [ ] The weak capture in `EditorViewController`, as a behaviour change with a
      test for the case the comment describes
- [ ] `ProcessPipes.drain(onOutput:)` takes a `@Sendable` closure, and the
      callers follow
- [ ] `rasterScale` in both renderers, one decision for both
- [ ] The four tidying ones
- [ ] Decide whether the vendored grammars get a flag, and say why either way
- [ ] Decide how a warning gets noticed next time, and put that in place
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does, if anything
      user-visible changed — the weak capture is the only candidate
