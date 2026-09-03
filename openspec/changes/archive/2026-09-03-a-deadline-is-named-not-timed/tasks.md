## 1. Name the mechanisms

- [x] 1.1 `LSPClient.ClientError` conforms to `Equatable`, so a test can expect
  one case by name.
- [x] 1.2 `aRequestAgainstASilentServerGivesUpOnTime` expects
  `.timedOut("textDocument/hover")` and prints the elapsed time with the load.
- [x] 1.3 `aRuntimeThatNeverAnswersIsGivenUpOnAndSaidOnce` keeps
  `reason.contains("did not answer")` and its lower bound, loses the
  sixty-second midpoint, and prints the number with the load.

## 2. Let a test be patient

- [x] 2.1 `signatureHelp(uri:position:timeout:)`, ten seconds by default.
- [x] 2.2 `saysWhichParameterIsBeingFilledIn` passes `Patience.seconds`.

## 3. Checked

- [x] 3.1 The suite: 4023 tests in 512 suites, exit 0, at load 25 over 14
  cores — with the two measurements printed rather than asserted, at 25.0 s and
  41.7 s against one-second deadlines, load 29 and 31.
- [x] 3.2 `make warnings` exit 0. `Scripts/file-size-allowed.txt` carries
  `LSPClient.swift` at 1203 for the `Equatable` note and the timeout's
  documentation.
