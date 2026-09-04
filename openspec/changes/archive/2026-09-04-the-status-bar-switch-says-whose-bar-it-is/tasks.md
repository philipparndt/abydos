## 1. Say it where it is read

- [x] 1.1 The settings help: which session, that its terminals all lose the
  bar, that it outlives the app, and only then what is untouched.
- [x] 1.2 Two toasts, since restoring is not the mirror image of hiding.

## 2. Say it where it is done

- [x] 2.1 `TmuxSettings.apply` and `TmuxMirror.setStatusBar` carry the scope
  and the lifetime, and why the old wording misled.

## 3. Read it back from the build

- [x] 3.1 **Nothing could read a help text from a run**, which is why a wrong
  one survived: every settings verb either sets a value or photographs the
  page, and this sentence is below the fold. `--settings-says "Page/Row"`
  prints a row's title and its help, matching part of a title and walking into
  groups. Read back from the built app:

      Terminal ▸ Hide tmux's own status bar
          … It sets `status off` on this project's session — not on the
          server, and nothing is written to ~/.tmux.conf — so other sessions
          keep their bar. This one loses it in every terminal attached to it,
          Abydos or not, and keeps it off after Abydos quits until this is
          turned back on.
- [x] 3.2 `make test` and `make warnings`, both clean by their exit codes —
  4038 tests in 514 suites, exit 0, at load 42.9 over 14 cores; `make warnings`
  exit 0. `main` was red on arrival for a reason of its own; see the commit
  beside this one.
