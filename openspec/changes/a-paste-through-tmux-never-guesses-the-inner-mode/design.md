## Context

`TerminalView.paste` sends a paste one of two ways. When `pty.ttyName` names a
tmux client it hands the text to tmux — `session(forClient:)` to find the
client's session, then `TmuxMirror.paste`, which loads a buffer and runs
`paste-buffer -p`, so tmux brackets the text where the inner pane asked and not
otherwise. When there is no tmux, or the tmux route returns false, it falls to
`sendPaste`, which writes `ESC[200~` … `ESC[201~` itself whenever
`emulator.bracketedPaste` is set.

That fallback is the leak. Under tmux, `emulator.bracketedPaste` is tmux's
forwarded mode — the outer client's — and the program that will read the bytes
is the inner zsh, which toggles its own mode as it runs commands and edits
lines. When the two disagree for an instant, the markers reach zsh literally:
`ESC[200~` loses its `ESC` to the line editor and leaves `[200~`, and `ESC[201~`
leaves a trailing `~`. The comment above the tmux path names this exact race and
guards the tmux path against it; the fallback still runs the race.

It fires intermittently because it fires only when the tmux route returns
false, and the likeliest reason is `session(forClient:)` returning nil: it
spawns `tmux list-clients` and matches the app's tty against `client_tty`, and
any momentary miss drops the paste to the guessing path. Two pastes in a row,
one clean and one broken, is that path firing once (reported 2026-09-10).

## Decisions

### 1. The decision is a pure function, so the fix is a test and not a race

`TmuxPaste.plan(text:throughTmux:tmuxAccepted:bracketedPaste:)` in the Kit
returns what to put on the wire: `.tmuxTook` when tmux accepted it, `.write(String)`
otherwise. The rule it encodes:

- **Not a tmux client**: `.write` the text, with markers when `bracketedPaste`
  — `sendPaste` as it is today, where the emulator's own mode is the authority
  because there is no tmux between us and the program.
- **A tmux client, tmux accepted the paste**: `.tmuxTook`, nothing on the wire.
- **A tmux client, tmux did not accept it**: `.write` the **raw text, never the
  markers**. We cannot know the inner pane's mode — that is tmux's to know, and
  tmux is the thing that just failed — so the worst case is a multi-line paste
  that runs line by line, which is annoying, against a marker in the command
  line, which is a bug. The markers are only ever written where nothing else
  knows the mode better than we do, which through tmux is never.

The view keeps the async orchestration; the branch that used to guess is this
function, and a test asserts that a failed tmux paste writes no `ESC[200~`.

### 2. The tmux paste is retried before it is given up on

`session(forClient:)` and `TmuxMirror.paste` are each a subprocess round-trip,
and a single miss should not decide a paste. The tmux route is attempted a
small, bounded number of times — three, spaced by a few milliseconds — before
`tmuxAccepted` is false. A retried lookup answers the transient miss that the
report is; the raw-text fallback catches the genuine failure that a retry
cannot.

*Ruled out: the pane's remembered session name instead of `list-clients`.* The
pane knows the session it attached with (`mirroredTmuxSession`), and it is
tempting to target that and skip the lookup. But a client whose session was
switched (`tmux switch-client`) has moved on, and the remembered name is then
stale while `list-clients`'s `client_session` is current. The lookup is the
correct source; making it not *silently* lose is the fix, not replacing it.

*Ruled out: writing the markers but stripping them if tmux later reports the
inner mode.* There is no "later" — the bytes are on the wire the moment they
are written, and the mode can change between the check and the read. Only not
writing them is safe.

### 3. Reproduced against a real tmux, then fixed

`TmuxPasteTests` already runs a real tmux and checks the happy path. A test is
added for the leak's shape: a pane whose inner program has bracketed paste
**off** while the outer client has it on — the disagreement — and a paste that,
before the fix, could arrive with `[200~` and after it arrives clean because
the fallback writes no markers. And the pure function is tested directly for the
four cases, which is the claim that does not need a race to hold.

## What was measured

*(the runs, once made)*

## Release note

> **A paste into a tmux terminal no longer leaks `[200~`.** Pasting through
> tmux, a rare miss in reaching tmux used to fall back to writing
> bracketed-paste markers from the outer terminal's mode rather than the
> shell's, and when they disagreed the marker landed in the command line. The
> tmux paste is retried now, and if tmux truly cannot be reached the text is
> pasted plainly — never with a marker the shell did not ask for.

## Open Questions

None.
