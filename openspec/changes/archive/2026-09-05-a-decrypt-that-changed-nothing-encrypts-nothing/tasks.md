## 1. The baseline on the tab

- [x] 1.1 `Tab` gained `decryptedBaseline: String?` — the plaintext exactly as
  `sops` returned it — with the comment that says why it is text and not a
  digest: the rope and the undo tree already hold the whole of it, and a hash
  would cost a save-time computation to save kilobytes. `decrypt(_:)` sets it
  from `result.stdout`; `lockAgain(_:)` clears it, so no path leaves a stale
  baseline behind.
- [x] 1.2 `DecryptedBuffer` gained `baseline: String?`, defaulting to nil in
  `init` so every existing call site compiles; `parkDecryptedTabs` passes
  `tab.decryptedBaseline`, `restoreDecrypted(_:)` puts it back — the switch
  round trip keeps the skip working for the edited-then-undone buffer, which
  re-deriving it from `isEdited` would lose.

## 2. The skip

- [x] 2.1 `encryptAndSave(_:)` and `encryptAndSaveSync(_:)` gained the same
  early branch after the `hasChangedOnDisk` guard — the guard stands first: a
  file that moved since the decrypt is not the file this baseline came from,
  and its refusal is the one it already gets. Text equal to the baseline means
  `lockIfUnchanged(_:)` and `true`: no `sops`, no write, the buffer locked
  back exactly as the chip locks an unedited buffer.
- [x] 2.2 The quit gate's parked loop in
  `MainWindowController+Layout.settleDecryptedBuffersForQuit` — which does not
  go through the editor's save path — compares `parked.buffer.text` with
  `parked.buffer.baseline` before it runs `sops`, and on a match discards the
  park: the ciphertext on disk already is this text's version. The open-tab
  branch and the close dialog reuse `encryptAndSaveSync`, which has the skip;
  the modal alerts themselves stay undriven, as the sops change left them.

## 3. Proving it

- [x] 3.1 Driven on 2026-09-05: a scratch project under the agent scratchpad
  with an `age` key made for the run and real `sops` 3.13.3, a debug build
  under the throwaway id `de.rnd7.abydos.sops-skip`, `SOPS_AGE_KEY_FILE`
  naming the run's key. Four runs, the file shasummed from the terminal before
  and after each:
  - *Read only:* `report,decrypt,settle,report,encrypt,settle,report` — the
    reports read encrypted (24 lines, ciphertext sha `af2f5e38a983b40f`), then
    decrypted (9 lines, digest `fb7785d990892123`, the same digest
    `sops --decrypt` gives at a terminal), then encrypted holding the same
    ciphertext digest; the file on disk `af2f5e38…` before and after, byte
    for byte.
  - *Edit undone:* the driver gained an `undo` step for this. Typed
    `zz9plural`, undone: the report reads `decrypted edited=true` — dirty,
    with the digest back at the plaintext's, which is the `isDirty` lie the
    report is named for — then `encrypt` left the file at `af2f5e38…`.
  - *Control, an edit still encrypts:* typed without the undo, `encrypt` —
    the file rewritten (`23976c59…`), and `sops -d` at the terminal gives the
    text with the typed line in it.
  - *The park:* decrypt in A, `--switch-project` to B at 7 s and back at
    12 s; the restored buffer reports decrypted with the plaintext's digest
    (the baseline came back through the park), `encrypt` skipped, and the
    file `195c6249…` before and after, byte for byte.
- [x] 3.2 `DecryptedBuffersTests.theBaselineSurvivesThePark` — a buffer
  edited and undone back parks with its baseline and takes it back out; the
  two sops suites green, 16 tests.

## 4. Finishing

- [x] 4.1 `Scripts/file-size-allowed.txt` raised for `EditorViewController.swift`
  5328 → 5372: the baseline field and its comment, the set and the clear,
  `lockIfUnchanged` and its doc, the park and restore carry, the driver's
  `undo` step — reasons said aloud, one line wider, the debt the file records.
- [x] 4.2 Green by their exit codes, twice — the second run after the
  indentation of three blocks was corrected: `make test` 4077 tests in 519
  suites, exit 0 with the suite's standing two container-runtime issues, load
  45.27 over 10 cores; `make warnings` exit 0, no warnings.