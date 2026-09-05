## 1. The rules and the commands, in AbydosKit

- [x] 1.1 `SopsFile`: `formats` by extension (yaml, yml, json, env, ini), `looksEncrypted(name:head:)` from a bounded read of up to 256 KB (`ENC[` and a top-level `sops` key, the JSON form too), and `head(of:)`. Tests as sentences: an encrypted yaml is one; a yaml with a `sops:` key and no ciphertext is not; `ENC[` in a string with no block is not; a `.txt` is not however it reads; the block at the end of a long file is still found.
- [x] 1.2 `Sops`: (`version()` left out — the chip says *sops not found* and the toast carries `sops`'s own refusal of an unknown flag, which is the same sentence one step later.) `locate()` through `Executables.locate("sops")` with `ABYDOS_SOPS` overriding for a driven run; `version()`; `decrypt(file:)` and `encrypt(text:as:format:)` — the two argument lists, stdin for the plaintext, `ProcessPipes.drain`, a `ProcessResult` back. Tests for the argument lists and for the not-installed answer; nothing that needs `sops`.
- [x] 1.3 `DecryptedBuffers`: park and take by standardised root and file, carrying text, edited flag and caret; `editedFiles(for root:)` and `allEdited()` for the quit gate. Tests: parked for A is not found for B; taking empties; a later park replaces; a trailing slash is the same root.
- [x] 1.4 `PreviewFacts.isSopsEncrypted`, computed where the go3mf fact is, and nowhere a tree walk asks.

## 2. The tab and the bar

- [x] 2.1 The tab's decrypted state: on `Tab`, set by the decrypt, cleared by nothing but closing; `TextDocument` declines auto-save while it is set; `onTextChanged` and the open/close announcements skip the language server while it is set; `reloadExternallyChangedFiles` skips it as it skips a dirty document.
- [x] 2.2 The chip in `EditorStatusView` after the lock: three looks — encrypted, decrypted, not found — with tooltips; hit test, hover and cursor as the lock has; state pushed through `refreshStatus(from:)` beside the lock's, never worked out in `draw`.
- [x] 2.3 The decrypt: `Sops.decrypt`, off the main thread, the spinner meanwhile; `replaceAllText(with:)` on the answer; the decrypted state set; the covers turned on through `setConcealsSecrets` by the state as well as by the name; the toast with `sops`'s stderr on refusal.
- [x] 2.4 The save: ⌘S and the chip route a decrypted buffer to `Sops.encrypt` with `--filename-override`; the disk state checked first and a moved file refused; the ciphertext written with the atomic write `save()` uses; the document clean and its disk state recorded; the toast on refusal. `sops --version` read once and a `sops` without the flag said on the chip.
- [x] 2.5 View ▸ Decrypt with sops beside Reveal Secrets; a no-op on any other tab rather than validated, since the chip is the control and the item is the keyboard's way to it.

## 3. The park and the quit

- [x] 3.1 On a project switch, decrypted tabs are parked in `DecryptedBuffers` — held by the window beside `sessions` and `drafts` — instead of being asked about; when the session reopens the file, the tab is built decrypted from the park before it is drawn.
- [x] 3.2 `applicationShouldTerminate`: (not driven — a modal alert at quit has no driver; the open-tab branch reuses `encryptAndSaveSync`, which the close dialog also uses, and the parked branch is the same three lines on the park.) per edited decrypted buffer, open or parked, *Encrypt and save* / *Discard* / *Cancel*; cancel returns `.terminateCancel`; a failed encrypt keeps the app open with the toast.

## 4. Proving it

- [x] 4.1 The driver: `--sops <steps>` with `report` (state, line count, SHA-256 of the text — never the text), `decrypt`, `encrypt`, `type:`; `ABYDOS_SOPS` honoured.
- [x] 4.2 Driven on 2026-09-04 with `sops` 3.13.3 and an `age` key made for the run, on a 53-value file: `encrypted` (69 lines) → `decrypted` (54 lines, covers on, digest `caecb86c…`) → typed → `decrypted, edited` (`6f972ebd…`) → `encrypt` → `decrypted`, clean. `sops --decrypt` at the terminal afterwards gives text with digest `6f972ebd…` and the typed first line. A grep for the distinctive plaintext under the project and under `$TMPDIR` finds nothing. Capture of the bar with *Secrets hidden* and *SOPS · decrypted* taken. Amended on 2026-09-05 and driven again: the decrypt arrives `revealed=true` with the lock open; `encrypt` returns the buffer to the fresh ciphertext (`encrypted`, 69 lines) so the chip can decrypt it again in place, which the next `decrypt` step does with the edited digest; a press on the clean decrypted buffer locks it again from disk.
- [x] 4.3 Driven: decrypt and edit in A, `--switch-project` to B at 7 s and back at 11 s — the tab returns `decrypted, edited` with the same digest, and nothing under A holds the plaintext. `ABYDOS_SOPS=/nonexistent` gives `sops-missing` and a press that does nothing; a stand-in that exits 1 leaves the buffer `encrypted` with the toast *Could not decrypt secrets-dev.yaml: age: no identity matched any of the recipients*. A file rewritten on disk during the decrypt refuses the save with *changed on disk*.
- [x] 4.4 The tool's own times on the 53-value file at load 8 over 10 cores: `sops --decrypt` 0.01–0.02 s, `sops --encrypt` from stdin 0.01–0.02 s, three runs each. The app adds one process spawn and one buffer replace to either.

## 5. Finishing

- [x] 5.1 Said in `docs/release-notes-0.14.0.md`, with the whole-file re-encryption and the GUI environment both named.
- [x] 5.2 Green on 2026-09-04 by their exit codes: `make test` 4076 tests in 519 suites, exit 0, load 61.0 over 10 cores, and again after the 2026-09-05 amendments at load 82.9; `make warnings` exit 0 after `Scripts/file-size-allowed.txt` was raised for `EditorViewController.swift` (4976 → 5321, the last 37 for the lock-again path: the SOPS section — state, decrypt, encrypt, park, restore, driver — and the chip in the status view, all on the group's and the view's private state), `AppDelegate.swift` (3748 → 3769: the quit gate, the menu item and the driver dispatch) and `LaunchOptions.swift` (1595 → 1598: the flag).
