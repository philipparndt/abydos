## 1. The passphrase's way to gpg

- [x] 1.1 `Sops.gpgWrapper()` — the wrapper written once under the app's
  Application Support directory, mode 0700, `exec gpg --batch
  --pinentry-mode loopback --passphrase-fd 3 "$@"`; its path is what
  `SOPS_GPG_EXEC` carries.
- [x] 1.2 `Sops.decrypt(_:passphrase:)` — a pipe whose read end is moved to
  descriptor 3 with `FD_CLOEXEC` cleared before `sops` starts, the passphrase
  written to the write end and the end closed, the read end closed after
  `sops` exits. Without a passphrase, the run is exactly today's.
- [x] 1.3 `Sops.needsPassphrase(stderr:)` and `Sops.keyNamed(in stderr:)` —
  gpg's phrases for a pinentry it could not run and for a bad passphrase,
  and the key ID when gpg printed one.
- [x] 1.4 `Passphrases` — the in-memory keep, keyed by key ID or project
  root, cleared at quit; no persistence anywhere.
- [x] 1.5 Tests: a fake `sops` and a fake `gpg` in sh under the test's
  scratch — sops runs `$SOPS_GPG_EXEC`, gpg reads fd 3 and prints its length
  — proving the descriptor survives both execs; `needsPassphrase` over
  recorded gpg 2.4 messages; the keep; and, when `gpg` and `sops` are on the
  machine, a key made with `gpg --batch --gen-key` in a throwaway
  `GNUPGHOME`, a file encrypted to it, and a decrypt through the pipe.

## 2. The field in the bar

- [x] 2.1 `EditorStatusView` — a secure field laid over the chip's rect while
  asking, a measured member of the scaled controls with the bar's font and
  height, the key or the file in its placeholder, gpg's sentence as its
  tooltip; Return and Escape as the spec says; the text read once and the
  field cleared.
- [x] 2.2 `EditorViewController.decrypt` — on a passphrase-shaped failure,
  the kept passphrase first, then the bar's field; the retry through
  `decrypt(_:passphrase:)`; a wrong passphrase keeps the field with gpg's
  sentence; success keeps the passphrase for the sitting. Any other failure
  keeps the toast.
- [x] 2.3 ⌥ on *Lock* forgets the kept passphrase, said in the chip's tooltip.

## 3. Proving it

- [x] 3.1 The sops driver gains `passphrase:<text>`, `cancel-passphrase` and
  `forget`, and `report` says the ask's placeholder and how many passphrases
  are kept. No new flag: `ABYDOS_SOPS` already stands a fake sops in, and
  `ABYDOS_GPG` — read by the wrapper — does the same for gpg.
- [x] 3.2 Driven on 2026-09-07 with a fake sops that fails as gpg does
  without a pinentry until a wrapper is named, and a fake gpg that reads the
  descriptor and writes a proof: `press` → `ask="Passphrase for key
  8A1F2B3C4D5E6F70"`; `passphrase:wrong` → `ask="Wrong passphrase — try
  again"`, still encrypted; `passphrase:hunter2` → `state=decrypted kept=1`
  with the plaintext's four lines; `press` → locked; `press` → decrypted
  again with `ask=none`. The proof file: `fd=3 length=7`, and the passphrase
  in neither gpg's arguments nor its environment. Screenshot
  `sops-field.png`: the field in the bar where the chip was.
- [x] 3.3 The real key is the unit test's: `aRealKeyWithAPassphraseDecryptsThroughThePipe`
  makes an RSA key with a passphrase in a throwaway `GNUPGHOME` under
  `/tmp` (the agent's socket path is capped at 104 bytes, which the
  temporary directory exceeds), encrypts a file to it with the machine's
  sops, is refused with a wrong passphrase in gpg's words, and decrypts with
  the right one through the pipe. `ps` is the fake gpg's check in 3.2.

## 4. Finishing

- [x] 4.1 `Scripts/file-size-allowed.txt`: `EditorViewController.swift`
  5998 → 6135, the field in the status view and the retry in the decrypt
  path. `EditorAreaController` would have crossed eleven hundred, so its
  passphrase handling is `EditorAreaController+Passphrase.swift`.
- [x] 4.2 `docs/release-notes-0.17.0.md` has the section.
- [x] 4.3 No `.abydos/backlog/spec/*.md` is made untrue: the directory is
  gone from the tree.
- [x] 4.4 `make test` 4280 tests in 547 suites, exit 0 with the two standing known issues, load 17.6 over 10 cores; `make warnings` exit 0.
  with the run's load said.
