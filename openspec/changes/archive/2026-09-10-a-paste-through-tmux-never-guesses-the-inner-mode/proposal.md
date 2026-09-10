## Why

The maintainer, 2026-09-10: a string pasted twice into a tmux pane, the
clipboard unchanged, came out once as `[200~cd …kit~` and once clean. `[200~`
is the front of a bracketed-paste marker — `ESC[200~` … `ESC[201~`, which wraps
a paste so a shell knows it arrived at once and does not run each line as it
lands. When those bytes reach a shell that is not in bracketed-paste mode the
`ESC` is absorbed and `[200~` is left in the command line; the trailing `~` is
`ESC[201~` losing its own `ESC` the same way. So both markers reached zsh as
literal bytes. It happens from time to time, which is the tell.

Reading `TerminalView+Composition.swift` finds two paste paths into a tmux
pane:

- **The intended one**: hand the text to tmux (`TmuxMirror.paste`, running
  `paste-buffer -p`). tmux knows the inner pane's paste mode and brackets or
  does not; nothing races. The code's own comment explains exactly this and why
  it is safe.
- **The fallback**, `sendPaste`, which writes `ESC[200~` … `ESC[201~` itself,
  deciding from `emulator.bracketedPaste`. Under tmux that flag is tmux's
  *forwarded* mode, the outer client's, not the inner zsh's — and when they
  disagree for an instant the markers land literally.

The fallback fires whenever the tmux path returns false. Its likeliest trigger
is `TmuxMirror.session(forClient:)` returning nil: it spawns `tmux list-clients`
and matches the app's tty against `client_tty`, and any momentary miss drops the
paste to the guessing path. Two pastes in a row, one clean and one broken, is
that path firing once — and the guard the comment describes protects only the
intended path, while the fallback still guesses.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-10.

## What Changes

- **A paste into a tmux client never guesses.** When `pty.ttyName` names a tmux
  client, `sendPaste`'s marker-writing is not the fallback. The tmux paste is
  retried a small, bounded number of times, and only a genuine, repeated
  failure to reach tmux falls back — and that fallback pastes the raw text
  without markers rather than with markers the inner mode may reject, so the
  worst case is a multi-line paste that runs line by line, never a marker in
  the command line.
- **The session lookup is made less fragile.** Whether `session(forClient:)`
  can answer from something the pane already knows — the session it attached
  with — rather than a fresh `list-clients` per paste, decided in the design;
  a lookup that cannot miss is better than one retried.
- **Reproduced before it is fixed.** A driven run against a scratch tmux
  session forces the fallback — the tmux route made to fail — and reads the
  pane back to show `[200~` arriving, then shows it gone once the fallback no
  longer writes markers.

## Capabilities

### Modified Capabilities

- `terminal`: what a paste into a tmux pane may put on the wire, and that it is
  never a bracketed-paste marker the inner program did not ask for.

## Impact

- **AbydosApp**: `TerminalView+Composition.swift`, the paste paths.
- **AbydosKit**: `TmuxMirror.paste` and `session(forClient:)`, the retry and
  the lookup.
- **Driving**: a paste step that forces the tmux route to fail and reads the
  pane, so the leak is a reproduction and not a theory.
