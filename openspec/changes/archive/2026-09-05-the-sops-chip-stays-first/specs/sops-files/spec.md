## MODIFIED Requirements

### Requirement: A SOPS file is recognised when it opens and says so in the status bar

A file SHALL be treated as a SOPS file when its extension is one SOPS formats
— `yaml`, `yml`, `json`, `env`, `ini` — and its contents, read once at open
and bounded, hold both an `ENC[` value and a top-level `sops` key. The
editor's status bar SHALL show a chip as its first item, at the left edge,
reading *SOPS · encrypted* for such a file, and nothing for any other file.
The chip SHALL keep that place in every state — encrypted, decrypted, edited,
dimmed — whether the secrets lock is shown or not, because it is a button, and
a button that moves between its two states is a button nobody learns to reach
for; the lock, when the file conceals, SHALL follow the chip rather than lead
it. When `sops` cannot be found the chip SHALL be shown dimmed with the reason
in its tooltip.

#### Scenario: an encrypted values file

- **GIVEN** `secrets-dev.yaml` encrypted with `sops`, opened in the editor
- **WHEN** the status bar is looked at
- **THEN** a chip at the left edge, the first item in the bar, reads
  *SOPS · encrypted*

#### Scenario: the chip keeps its place through a decrypt

- **GIVEN** `secrets-dev.yaml` encrypted, its chip the first item at the
  bar's left edge
- **WHEN** the chip is pressed and the values arrive revealed, the lock shown
- **THEN** the chip's left edge is where it was, reading *SOPS · decrypted*,
  and the lock stands to its right

#### Scenario: a YAML file with a sops key and no ciphertext

- **GIVEN** a YAML file with a top-level `sops:` key and no `ENC[` value
- **WHEN** it is opened
- **THEN** there is no chip

#### Scenario: sops is not installed

- **GIVEN** no `sops` on the login shell's `PATH`
- **WHEN** a SOPS file is opened
- **THEN** the chip is dimmed and its tooltip says `sops` was not found
