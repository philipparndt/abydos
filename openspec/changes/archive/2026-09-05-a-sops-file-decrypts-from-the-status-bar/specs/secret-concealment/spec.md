## MODIFIED Requirements

### Requirement: Dotenv values are concealed by default

Values SHALL be drawn under an opaque cover from the moment a file opens when
its name has a dotenv shape — `.env`, `.env.*`, `*.env`, `*.dec` — and a SOPS
file decrypted in the editor SHALL conceal the same way, whatever its name: a
decrypted buffer is a `.dec` that never touched a disk. It arrives revealed,
since the decrypt is the explicit act, and is shut by the lock and the idle
limit as any covered file is. Decided by name shape for files on disk and by
the tab's decrypted state for a buffer, never by looking for entropy in an
arbitrary file.

#### Scenario: a dotenv file opens covered

- **GIVEN** a `.env` file opened in the editor
- **WHEN** it is looked at
- **THEN** every value after `=` is under a cover

#### Scenario: a decrypted SOPS file conceals once the lock is shut

- **GIVEN** `secrets-dev.yaml` decrypted in the editor, its values shown
- **WHEN** the lock is pressed
- **THEN** every value is under a cover, as a `.dec` of the same file would be

### Requirement: A value is shown only by an explicit action

A covered value SHALL be revealed only by the lock on the left of the
editor's status bar — labelled *Secrets hidden* while shut and *Secrets
shown* while open — or by View ▸ Reveal Secrets, the same act in two places.
The lock SHALL keep its place on the left when the SOPS chip is shown beside
it; the chip is the file's encryption and the lock is its covers, and
pressing one SHALL NOT change the other. Clicking a cover SHALL NOT reveal it
and SHALL say where the lock is.

#### Scenario: the lock beside the chip

- **GIVEN** a decrypted SOPS file with its values covered
- **WHEN** the lock is pressed
- **THEN** the values are shown and the chip still reads *SOPS · decrypted*
