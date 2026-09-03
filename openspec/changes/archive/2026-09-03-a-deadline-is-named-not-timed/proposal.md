## Why

Three tests kept `make test` red while the code under them worked. Asked to
chase them so the suite can gate again.

All three were the same mistake, from two directions. Each asserted something
about *how long* a mechanism took in order to say *which* mechanism it was —
and the suite's own parallelism decides how long anything takes:

- `saysWhichParameterIsBeingFilledIn` asked sourcekit-lsp for signature help and
  inherited `LSPClient.request`'s ten-second default. That default is a
  typist's: the request goes out as somebody types the `(`, and an answer after
  they have finished typing the arguments is no answer. A test asking the same
  question for its *content* was betting on the machine.
- `aRequestAgainstASilentServerGivesUpOnTime` asked for any `ClientError` and
  then read the clock — under thirty seconds — to say it was the deadline that
  threw. Measured red at 35, 37 and 40 seconds.
- `aRuntimeThatNeverAnswersIsGivenUpOnAndSaidOnce` put a sixty-second midpoint
  between a one-second deadline and the program's own `sleep 120`. Measured red
  at 97 seconds.

The last two were already guarded by `Stopwatch.mayClassify`, and went red
anyway: the guard reads a one-minute load average and is asked *before* the
wait, so the suite's own parallelism arrives after it has answered. That lag is
written down in `mayClassify`'s own documentation as a known hole.

What the run now prints, having stopped asserting it, is the argument: a
one-second deadline firing at 25.0 s and at 41.7 s, at load 29 and 31 over 14
cores. No midpoint survives that, and both deadlines were working.

## What Changes

- **A classification names the mechanism instead of timing it.**
  `LSPClient.ClientError` becomes `Equatable`, so the LSP test expects
  `.timedOut("textDocument/hover")` exactly — `.notRunning` is checked before
  the request is sent, and `.failed` carries a reply a server told to
  `sleep 120` cannot send. The runtime test already asserted
  `reason.contains("did not answer")`, which is the deadline's own words and
  which the sleeping program can never produce; its clock bound went.
- **The duration is said, with the load beside it**, rather than asserted —
  which is what this capability already requires of a *performance* bound and
  what `MachineLoad.said` exists for.
- **A test asking for content waits as long as the machine needs.**
  `signatureHelp` gains its own `timeout`, ten seconds by default for the app,
  and the test passes `Patience.seconds` — the number whose own documentation
  names "a language server to answer".
- Lower bounds stay. Load can only ever make those later.

## Capabilities

### Modified Capabilities

- `test-timing`: gains what a test may use a clock *for*, beside what it may
  assert about one.

## Impact

- **AbydosKit**: `ClientError: Equatable`; `signatureHelp(uri:position:timeout:)`.
- **Tests**: three of them, and two fewer wall-clock assertions in the suite.
- **The gate**: `make test` returns 0 at load 25 over 14 cores, which is the
  first time today it has done so on a machine anybody was using.
