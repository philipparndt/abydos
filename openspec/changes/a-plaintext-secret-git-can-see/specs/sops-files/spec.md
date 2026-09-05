## ADDED Requirements

### Requirement: A plaintext file a creation rule matches is offered encryption

The SOPS chip SHALL appear reading *SOPS · encrypt* — an offer, not a
warning — on a plaintext file whose path a creation rule in the project's
`.sops.yaml` matches, and pressing it SHALL pipe the buffer through
`sops --encrypt` under the file's own name, write the ciphertext over the file
atomically, and leave the tab as opening an already-encrypted file leaves it:
the chip reading *encrypted*, the ciphertext in the buffer, and nothing
decrypted held anywhere. A project with no `.sops.yaml`, and a path no
creation rule matches, SHALL show no chip and SHALL say nothing: most files
are not meant to be encrypted. A rule this app cannot read SHALL count as no
match, so a missing offer is the only failure of the reading. A failed
`sops --encrypt` SHALL leave the file exactly as it was and SHALL say why.

#### Scenario: a matching plaintext file offers the press

- **GIVEN** `.sops.yaml` with a creation rule whose `path_regex` matches `secrets/dev.yaml`, and that file in plaintext
- **WHEN** it is opened
- **THEN** the status bar's SOPS chip reads *SOPS · encrypt*

#### Scenario: pressing encrypts the file in place

- **GIVEN** `secrets/dev.yaml` open with the chip reading *SOPS · encrypt*
- **WHEN** the chip is pressed
- **THEN** the file on disk is SOPS ciphertext, the buffer shows it, and the chip reads *SOPS · encrypted*

#### Scenario: a file no rule matches is not asked about

- **GIVEN** `README.md` in the same project, matched by no creation rule
- **WHEN** it is opened
- **THEN** no SOPS chip is shown

#### Scenario: no rules at all

- **GIVEN** a project with no `.sops.yaml`
- **WHEN** a plaintext `secrets.yaml` is opened
- **THEN** no SOPS chip is shown

#### Scenario: a refused encrypt changes nothing

- **GIVEN** `secrets/dev.yaml` whose rule names a key this machine does not hold
- **WHEN** the chip is pressed
- **THEN** the file is byte for byte what it was and the failure is said
