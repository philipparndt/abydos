# Terminal

## ADDED Requirements

### Requirement: A paste through tmux never writes a marker the inner program did not ask for

When a pane is a tmux client, the terminal SHALL paste by handing the text to
tmux, and SHALL retry that a bounded number of times before treating it as
failed. Only when tmux genuinely cannot be reached SHALL the terminal write the
text itself, and then as raw text with no bracketed-paste markers — because
through tmux the inner program's paste mode is tmux's to know, not the outer
terminal's, and a marker written on a guess lands in the command line. When a
pane is not a tmux client the terminal SHALL write the text with markers exactly
when its own bracketed-paste mode is set, as before, the emulator's mode being
the authority there.

Reported 2026-09-10: a string pasted twice into a tmux pane, the clipboard
unchanged, arrived once with `[200~` in the command line and once clean — the
fallback path writing markers from the outer mode when the two disagreed.

#### Scenario: tmux takes the paste

- **GIVEN** a pane that is a tmux client
- **WHEN** text is pasted and tmux accepts it
- **THEN** nothing is written to the pane directly; tmux brackets it or not

#### Scenario: tmux cannot be reached

- **GIVEN** a pane that is a tmux client
- **WHEN** text is pasted and the tmux paste fails every retry
- **THEN** the raw text is written, containing no `ESC[200~` or `ESC[201~`

#### Scenario: a pane with no tmux

- **GIVEN** a pane that is not a tmux client, its bracketed-paste mode on
- **WHEN** text is pasted
- **THEN** it is written wrapped in `ESC[200~` and `ESC[201~`, as before

#### Scenario: the inner mode disagrees with the outer

- **GIVEN** a real tmux whose client has bracketed paste on and whose inner
  program has it off
- **WHEN** a paste falls back to the terminal writing it
- **THEN** what the inner program reads has no marker in it
