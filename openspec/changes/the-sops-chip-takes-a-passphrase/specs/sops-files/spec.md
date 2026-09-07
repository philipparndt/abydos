## MODIFIED Requirements

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

When the decrypt fails because gpg could not ask for the key's passphrase,
the chip's place in the status bar SHALL become a secure field naming the key
when gpg named it, with gpg's sentence as its tooltip; Return SHALL retry the
decrypt with the passphrase and Escape SHALL put the chip back. The passphrase
SHALL reach gpg on a file descriptor through a wrapper named by
`SOPS_GPG_EXEC`, and SHALL appear in no argument, no environment variable, no
file, no log and no toast. A passphrase that worked SHALL be kept in memory
for the sitting, keyed to the key, and tried before the field is shown again;
it SHALL be written nowhere. A wrong passphrase SHALL keep the field and say
so in it.

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

#### Scenario: a key with a passphrase and no pinentry

- **GIVEN** a SOPS file encrypted to a PGP key whose passphrase the agent does not have, and no pinentry the app can reach
- **WHEN** the chip is pressed
- **THEN** the chip becomes a passphrase field naming the key, and the buffer is unchanged

#### Scenario: the passphrase typed

- **GIVEN** that field
- **WHEN** the passphrase is typed and Return pressed
- **THEN** the buffer holds the plaintext, the chip reads *SOPS · decrypted*, and the passphrase is in no process argument, environment or file

#### Scenario: a wrong passphrase

- **GIVEN** that field
- **WHEN** a wrong passphrase is entered
- **THEN** the field stays, says the passphrase was wrong, and the buffer is unchanged

#### Scenario: asked once a sitting

- **GIVEN** a passphrase that worked, and the buffer locked again
- **WHEN** the chip is pressed
- **THEN** the buffer is decrypted without the field appearing

#### Scenario: a setup that needs no passphrase

- **GIVEN** an age key, or an agent that already holds the passphrase
- **WHEN** the chip is pressed
- **THEN** the buffer is decrypted and no field appears
