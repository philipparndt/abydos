## 1. The passphrase's way to gpg

- [ ] 1.1 `Sops.gpgWrapper()` — the wrapper written once under the app's
  Application Support directory, mode 0700, `exec gpg --batch
  --pinentry-mode loopback --passphrase-fd 3 "$@"`; its path is what
  `SOPS_GPG_EXEC` carries.
- [ ] 1.2 `Sops.decrypt(_:passphrase:)` — a pipe whose read end is moved to
  descriptor 3 with `FD_CLOEXEC` cleared before `sops` starts, the passphrase
  written to the write end and the end closed, the read end closed after
  `sops` exits. Without a passphrase, the run is exactly today's.
- [ ] 1.3 `Sops.needsPassphrase(stderr:)` and `Sops.keyNamed(in stderr:)` —
  gpg's phrases for a pinentry it could not run and for a bad passphrase,
  and the key ID when gpg printed one.
- [ ] 1.4 `Passphrases` — the in-memory keep, keyed by key ID or project
  root, cleared at quit; no persistence anywhere.
- [ ] 1.5 Tests: a fake `sops` and a fake `gpg` in sh under the test's
  scratch — sops runs `$SOPS_GPG_EXEC`, gpg reads fd 3 and prints its length
  — proving the descriptor survives both execs; `needsPassphrase` over
  recorded gpg 2.4 messages; the keep; and, when `gpg` and `sops` are on the
  machine, a key made with `gpg --batch --gen-key` in a throwaway
  `GNUPGHOME`, a file encrypted to it, and a decrypt through the pipe.

## 2. The field in the bar

- [ ] 2.1 `EditorStatusView` — a secure field laid over the chip's rect while
  asking, a measured member of the scaled controls with the bar's font and
  height, the key or the file in its placeholder, gpg's sentence as its
  tooltip; Return and Escape as the spec says; the text read once and the
  field cleared.
- [ ] 2.2 `EditorViewController.decrypt` — on a passphrase-shaped failure,
  the kept passphrase first, then the bar's field; the retry through
  `decrypt(_:passphrase:)`; a wrong passphrase keeps the field with gpg's
  sentence; success keeps the passphrase for the sitting. Any other failure
  keeps the toast.
- [ ] 2.3 ⌥ on *Lock* forgets the kept passphrase, said in the chip's tooltip.

## 3. Proving it

- [ ] 3.1 The sops driver gains `passphrase:<text>` and `report` says whether
  the field is showing and what its placeholder reads; `--sops-tools <dir>`
  points `ABYDOS_SOPS` and the wrapper's gpg at fakes under the scratchpad.
- [ ] 3.2 Driven with the fakes: the chip pressed, the field appearing with
  the key's name, the passphrase entered, the decrypt going through with the
  fake gpg reporting the passphrase's length and never its text, a wrong one
  keeping the field, and a second press after a lock asking nothing. A
  screenshot of the field in the bar.
- [ ] 3.3 With a real key where the machine has gpg and sops: the same,
  against a file encrypted in a throwaway `GNUPGHOME`, and `ps` during the
  decrypt showing no passphrase.

## 4. Finishing

- [ ] 4.1 `Scripts/file-size-allowed.txt` raised for `EditorViewController`
  by what the retry added, and no more.
- [ ] 4.2 Release notes section for the next version.
- [ ] 4.3 No `.abydos/backlog/spec/*.md` is made untrue: the directory is
  gone from the tree.
- [ ] 4.4 `make test` and `make warnings`, both clean by their exit codes,
  with the run's load said.
