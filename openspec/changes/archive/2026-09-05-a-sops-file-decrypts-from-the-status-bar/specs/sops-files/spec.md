# SOPS Files

## Purpose

How a SOPS-encrypted file is recognised in the editor, what the status bar
offers for it, where its plaintext lives and where it never goes, how a save
encrypts it, what survives a project switch, and what quitting asks.

## ADDED Requirements

### Requirement: A SOPS file is recognised when it opens and says so in the status bar

A file SHALL be treated as a SOPS file when its extension is one SOPS formats
— `yaml`, `yml`, `json`, `env`, `ini` — and its contents, read once at open
and bounded, hold both an `ENC[` value and a top-level `sops` key. The
editor's status bar SHALL show a chip beside the secrets lock reading *SOPS ·
encrypted* for such a file, and nothing for any other file. When `sops`
cannot be found the chip SHALL be shown dimmed with the reason in its
tooltip.

#### Scenario: an encrypted values file

- **GIVEN** `secrets-dev.yaml` encrypted with `sops`, opened in the editor
- **WHEN** the status bar is looked at
- **THEN** a chip beside the lock reads *SOPS · encrypted*

#### Scenario: a YAML file with a sops key and no ciphertext

- **GIVEN** a YAML file with a top-level `sops:` key and no `ENC[` value
- **WHEN** it is opened
- **THEN** there is no chip

#### Scenario: sops is not installed

- **GIVEN** no `sops` on the login shell's `PATH`
- **WHEN** a SOPS file is opened
- **THEN** the chip is dimmed and its tooltip says `sops` was not found

### Requirement: Pressing the chip decrypts into the buffer, and nowhere else

Pressing *SOPS · encrypted* SHALL run `sops --decrypt` on the file and put
what comes back on its standard output into the editor's buffer as one edit.
The chip SHALL then read *SOPS · decrypted*, and the values SHALL stand
revealed with the lock open — pressing *decrypt* is the explicit act the lock
demands, and the lock and the idle limit shut them as for any covered file. The plaintext SHALL exist only
in the document and its undo history: the app SHALL write no temporary
file, no `.dec` file and no scratch, SHALL NOT auto-save a decrypted buffer,
SHALL NOT write its text into the session on disk, and SHALL NOT send its
text to a language server. A decrypt that fails SHALL leave the buffer as it
was and say why in a toast, with what `sops` said.

#### Scenario: decrypting

- **GIVEN** a SOPS file open, a key `sops` can use
- **WHEN** the chip is pressed
- **THEN** the buffer holds the plaintext, shown, with the lock open; the chip reads *SOPS · decrypted*; and no file under the project or the temporary directory holds the plaintext

#### Scenario: auto-save does not touch it

- **GIVEN** auto-save on, and a decrypted buffer edited
- **WHEN** the auto-save delay passes
- **THEN** the file on disk is still the ciphertext

#### Scenario: no key

- **GIVEN** a SOPS file whose key is not available
- **WHEN** the chip is pressed
- **THEN** the buffer is unchanged, the chip still reads *encrypted*, and a toast carries `sops`'s reason

### Requirement: A decrypted buffer's values are the lock's

A decrypted buffer SHALL conceal its values as a dotenv file does, whatever
the file is called: revealed by the decrypt itself, shut by the lock or by
the idle limit, and shown again only by the lock or View ▸ Reveal Secrets.

#### Scenario: the lock shuts a decrypted yaml

- **GIVEN** `secrets-dev.yaml` decrypted in the editor, its values shown
- **WHEN** the lock is pressed
- **THEN** every value is under a cover and the lock reads *Secrets hidden*, and the chip still reads *SOPS · decrypted*

### Requirement: Saving a decrypted buffer encrypts it over the file

⌘S on a decrypted buffer, and the chip when the buffer is edited, SHALL pipe
the buffer into `sops --encrypt` on standard input under the file's own name,
so the project's `.sops.yaml` rules choose the keys, and SHALL write the
ciphertext over the file atomically. The buffer SHALL then hold the
ciphertext again, clean, with the chip reading *SOPS · encrypted*, so the
file can be decrypted again in place. Pressing the chip on a decrypted buffer
with no edits SHALL put the ciphertext back the same way. An encrypt that
fails SHALL leave the file and the buffer as they were and say why. A save
over a file that changed on disk since the decrypt SHALL be refused and say
so.

#### Scenario: edit and save

- **GIVEN** a decrypted buffer with one value changed
- **WHEN** ⌘S is pressed
- **THEN** the file on disk is ciphertext that `sops --decrypt` turns back into the edited text, the buffer shows that ciphertext, the tab is clean, and pressing the chip decrypts it again

#### Scenario: locking again without a save

- **GIVEN** a decrypted buffer with no edits
- **WHEN** the chip is pressed
- **THEN** the buffer shows the ciphertext from disk and the chip reads *SOPS · encrypted*

#### Scenario: the file moved underneath

- **GIVEN** a decrypted buffer, and the file rewritten on disk by something else since
- **WHEN** ⌘S is pressed
- **THEN** nothing is written and a toast says the file changed on disk

### Requirement: A decrypted buffer survives a project switch in memory

When the window leaves a project, every decrypted buffer SHALL be parked in
memory by project and file — its text, whether it is edited, and its caret —
and SHALL NOT be asked about or written anywhere. When the project is next
shown and the session reopens the file, the tab SHALL come back decrypted
with the parked text and edits. Parked buffers SHALL be kept for the life of
the app and not beyond.

#### Scenario: switch away and back with edits

- **GIVEN** `secrets-dev.yaml` decrypted and edited in project A
- **WHEN** the window switches to B and back to A
- **THEN** the tab is open, decrypted, edited as it was, and A's session file on disk holds none of the text

### Requirement: Quitting with edited plaintext asks, per file, and can be cancelled

The app SHALL ask before quitting while any decrypted buffer — open or
parked — is edited: per file, *Encrypt and save*, *Discard* and *Cancel*. *Encrypt
and save* SHALL run the save path and SHALL keep the app open if it fails.
*Cancel* SHALL stop the quit. An unedited decrypted buffer SHALL need no
answer.

#### Scenario: cancel keeps everything

- **GIVEN** an edited decrypted buffer parked for a project not in the window
- **WHEN** ⌘Q is pressed and *Cancel* chosen
- **THEN** the app stays open and the buffer is still parked with its edits

#### Scenario: encrypt and save on quit

- **GIVEN** an edited decrypted buffer
- **WHEN** ⌘Q is pressed and *Encrypt and save* chosen
- **THEN** the file on disk decrypts to the edited text and the app quits

### Requirement: A driven run proves a round trip without printing a value

A driven run SHALL be able to decrypt, edit and encrypt a SOPS file made for
the run with a key made for the run, and its reports SHALL name the state,
the line count and a digest of the buffer and SHALL NOT print the text.

#### Scenario: the round trip

- **GIVEN** a scratch project with an `age` key, a `.sops.yaml` naming it, and a file encrypted with `sops`
- **WHEN** the steps `report,decrypt,report,type:…,encrypt,report` run
- **THEN** the reports read encrypted, then decrypted and revealed with the plaintext's digest, then encrypted and clean, and `sops --decrypt` at a terminal gives the edited text
