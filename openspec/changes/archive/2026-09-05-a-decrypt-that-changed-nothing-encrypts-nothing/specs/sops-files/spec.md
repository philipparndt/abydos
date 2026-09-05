## MODIFIED Requirements

### Requirement: Saving a decrypted buffer encrypts it over the file

⌘S on a decrypted buffer SHALL pipe the buffer into `sops --encrypt` on
standard input under the file's own name, so the project's `.sops.yaml` rules
choose the keys, and SHALL write the ciphertext over the file atomically; the
chip on an edited buffer, the close dialog's *Save* and the quit gate's
*Encrypt and save* — for a buffer open or parked — SHALL take the same route.
The buffer SHALL then hold the ciphertext again, clean, with the chip reading
*SOPS · encrypted*, so the file can be decrypted again in place. Pressing the
chip on a decrypted buffer with no edits SHALL put the ciphertext back the
same way. A save whose buffer still holds exactly the plaintext the decrypt
returned SHALL be skipped: no `sops`, no write, the file keeping every byte
it has — the ciphertext on disk already is that text's version, and `sops`
encrypts with a fresh key every run, so an encrypt over unchanged text is a
new version of the file nobody edited into — and the buffer SHALL be locked
back to that ciphertext as any save locks it. The skip SHALL NOT wait for the
buffer to be marked clean: an edit undone back to the decrypt's own text is
unchanged the same way a never-touched buffer is. An encrypt that fails SHALL
leave the file and the buffer as they were and say why. A save over a file
that changed on disk since the decrypt SHALL be refused and say so.

#### Scenario: edit and save

- **GIVEN** a decrypted buffer with one value changed
- **WHEN** ⌘S is pressed
- **THEN** the file on disk is ciphertext that `sops --decrypt` turns back into the edited text, the buffer shows that ciphertext, the tab is clean, and pressing the chip decrypts it again

#### Scenario: a save that changed nothing writes nothing

- **GIVEN** a decrypted buffer holding the decrypt's own plaintext — never edited, or edited and undone back to it
- **WHEN** ⌘S is pressed, or the chip is pressed, or the quit gate's *Encrypt and save* is chosen
- **THEN** the file on disk is byte for byte what it was before the save, the buffer shows the ciphertext from disk, the tab is clean, and the chip reads *SOPS · encrypted*

#### Scenario: the skip survives a project switch

- **GIVEN** a decrypted buffer holding the decrypt's own plaintext, parked by a project switch and restored
- **WHEN** ⌘S is pressed
- **THEN** the file on disk is byte for byte what it was, and the buffer shows the ciphertext from disk

#### Scenario: locking again without a save

- **GIVEN** a decrypted buffer with no edits
- **WHEN** the chip is pressed
- **THEN** the buffer shows the ciphertext from disk and the chip reads *SOPS · encrypted*

#### Scenario: the file moved underneath

- **GIVEN** a decrypted buffer, and the file rewritten on disk by something else since
- **WHEN** ⌘S is pressed
- **THEN** nothing is written and a toast says the file changed on disk