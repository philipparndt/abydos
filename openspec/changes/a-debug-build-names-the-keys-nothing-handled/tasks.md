## 1. Where it says it

- [x] 1.1 Find what this project already logs from a debug build with, and use
      that rather than a bare `print`. If there is nothing, say so here and
      decide. **`DiagnosticLog.write(_:to:)`**, which is what the language
      service uses; this writes to `editor`, so it lands in
      `~/Library/Logs/Abydos/editor.log` beside `lsp.log`.
- [x] 1.2 Reproduce the count against the current SDK with the `grep` in the
      design, and record what it says today — 43 declared, 29 handled, 14
      possible when this was written. **Today it is 43 declared, 39 handled,
      four possible**: `selectLine`, `selectParagraph`, `selectToMark`,
      `selectWord`. Ten were taken in the four days between the item and the
      work, `moveBackward:` and `moveForward:` among them. The count is a test
      now — `EditorMotionCeilingTests` — so the number cannot go stale in
      silence again.

## 2. The naming

- [x] 2.1 `default:` names an unhandled selector whose name begins `move` or
      `select`, once per selector per process.
- [x] 2.2 Nothing is said for anything else that arrives there, `noop:` first
      among them.
- [x] 2.3 A held key that repeats says it once.
- [x] 2.4 Nothing at all in a release build, checked by building one rather than
      by reading the `#if`. **Checked by accident first**: `make build` is
      release by default (`CONFIG ?= release`), and the first driven run said
      "nothing unhandled has been pressed" with an empty log. `make build
      CONFIG=debug` then named both.

## 3. Confirmed against a real key

- [x] 3.1 A debug build, ⌃B pressed, `moveBackward:` named — which is one of the
      14 and does nothing today. **It is not, any more**: ⌃B was taken by 0495,
      so there is no key left that reaches an unhandled motion — all four
      remaining are `select…` and none has a default binding on this system,
      which is exactly why nobody noticed they were missing. Driven instead
      through `doCommand(by:)`, the same function a binding arrives at:

          MOTIONS: selectParagraph:, selectWord:
          editor: nothing handles selectWord:
          editor: nothing handles selectParagraph:

      `selectWord:` was sent twice and named once; `noop:` and `complete:` were
      sent and said nothing.
- [x] 3.2 A driven run of `--vertical-nav` or `--word-nav` in a debug build,
      printing whatever it sweeps up beside its own report. **Both swept, and
      the log stayed empty** — every key they press is handled today. That is
      the right answer and worth recording: the sweep is a detector that
      currently detects nothing, which is what "no bug nobody triggers" means in
      practice.

## 4. Finish

- [x] 4.1 Decide whether `.abydos/backlog/spec/editor.md` gains anything, and
      write the answer down here either way. **It does, and that file is gone** —
      the backlog was dropped between this being written and being applied, so
      the delta goes to the `editor` capability in `openspec/specs`. It earns a
      requirement because it is a promise about noise: only two families, once
      each, never in a release build. Without that written down, the next person
      to reach for `default:` has no reason not to log all of it.
- [x] 4.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 4.3 Write down what was ruled out: logging `default:` whole, a setting
      rather than `#if DEBUG`, and handling any of the 14 here.
