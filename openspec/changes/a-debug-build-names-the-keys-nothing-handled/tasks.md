## 1. Where it says it

- [ ] 1.1 Find what this project already logs from a debug build with, and use
      that rather than a bare `print`. If there is nothing, say so here and
      decide.
- [ ] 1.2 Reproduce the count against the current SDK with the `grep` in the
      design, and record what it says today — 43 declared, 29 handled, 14
      possible when this was written.

## 2. The naming

- [ ] 2.1 `default:` names an unhandled selector whose name begins `move` or
      `select`, once per selector per process.
- [ ] 2.2 Nothing is said for anything else that arrives there, `noop:` first
      among them.
- [ ] 2.3 A held key that repeats says it once.
- [ ] 2.4 Nothing at all in a release build, checked by building one rather than
      by reading the `#if`.

## 3. Confirmed against a real key

- [ ] 3.1 A debug build, ⌃B pressed, `moveBackward:` named — which is one of the
      14 and does nothing today.
- [ ] 3.2 A driven run of `--vertical-nav` or `--word-nav` in a debug build,
      printing whatever it sweeps up beside its own report.

## 4. Finish

- [ ] 4.1 Decide whether `.abydos/backlog/spec/editor.md` gains anything, and
      write the answer down here either way.
- [ ] 4.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 4.3 Write down what was ruled out: logging `default:` whole, a setting
      rather than `#if DEBUG`, and handling any of the 14 here.
