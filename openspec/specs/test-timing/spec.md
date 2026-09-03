# test-timing Specification

## Purpose
TBD - created by archiving change tests-wait-rather-than-sleep. Update Purpose after archive.
## Requirements
### Requirement: A test waits for the thing it is about

A test waiting for work that happens in its own process SHALL synchronise on that
work — a continuation the handler resumes, or a stream the test reads from — and
SHALL NOT sleep for a fixed duration in place of waiting.

#### Scenario: A framed message arriving in pieces

- **WHEN** `readsAMessageArrivingInPieces` feeds a framed message through
  `client.consume` in seven-byte slices
- **THEN** the test waits until the message handler has been called
- **AND** the assertions run after it, never before
- **AND** the test completes in microseconds rather than 200ms

#### Scenario: The suite is under load

- **WHEN** the suite runs with its own parallelism, at the load 35–40 this machine
  reaches during `make test`, or higher
- **THEN** a test that waits on an in-process signal passes
- **AND** it passes repeatedly, not on average

### Requirement: A wait has a failure bound, not an expected duration

Where tests share a helper for waiting, its timeout SHALL exist to fail a test that
is going to fail anyway, and SHALL NOT be the duration the passing case waits for. A
timeout being reached SHALL fail the test rather than allow it to continue or hang.

#### Scenario: The awaited thing never happens

- **WHEN** a test waits for a callback that is never called
- **THEN** the test fails within the timeout
- **AND** the failure names what was being waited for, rather than reporting a
  downstream assertion as wrong

#### Scenario: The awaited thing happens immediately

- **WHEN** the callback fires at once
- **THEN** the test proceeds at once, regardless of how generous the timeout is

### Requirement: A sleep that remains says what it stands in for

A `Task.sleep` left in a test SHALL carry a comment naming what it waits for and why
that thing cannot be awaited — a container starting, a language server coming up —
so that a considered sleep is distinguishable from an unexamined one.

#### Scenario: A live test waits on a container

- **WHEN** a live test sleeps while a container runtime starts
- **THEN** a comment says so, and says why no signal is available
- **AND** the sleep is not converted into a wait that could hang the suite

### Requirement: A performance bound states the condition it was measured in

A test asserting a timing budget SHALL record the measurements the budget was chosen
from, including the measurement taken with the rest of the suite running, since that
is the condition the assertion actually runs in.

#### Scenario: The fold budget

- **WHEN** `foldComputationIsReasonableOnHugeFile` asserts a budget
- **THEN** the numbers for the test alone, inside `make test`, and inside `make test`
  under load are recorded beside it
- **AND** the budget is not a value the suite's own parallelism can exceed about half
  the time

#### Scenario: Processor time is not treated as concurrency-independent

- **WHEN** a bound uses `cpuTime` to remove scheduling from a measurement
- **THEN** it is not assumed to have removed contention as well
- **AND** the bound accounts for the same arithmetic costing more cycles when
  thirty-odd threads compete for cache and memory bandwidth

### Requirement: A mechanism is named rather than timed

A test that needs to say *which* of two mechanisms ended something SHALL say so
by naming it — the error case it threw, or the words it reported — and SHALL NOT
infer it from how long it took, wherever such a name exists.

A duration MAY be used for that classification only where no name exists, and
then under `Stopwatch.mayClassify`. Its guard is not sufficient on its own: it
reads a one-minute load average and is asked before the wait, so the suite's own
parallelism arrives after it has answered.

Where a duration is interesting but not asserted, the test SHALL print it with
`MachineLoad.said`, so the log carries the number and the load it was measured
at.

#### Scenario: A request against a server that never answers

- **WHEN** a request with a one-second deadline is made to a server told to
  sleep for two minutes
- **THEN** the test expects the timed-out error for that method by name
- **AND** it does not assert how long the deadline took to fire
- **AND** the elapsed time is printed with the load beside it

#### Scenario: An inspect that gives up

- **WHEN** a runtime inspect with a one-second deadline is given up on
- **THEN** the reported reason is what identifies the deadline
- **AND** no upper bound is placed on the wait

### Requirement: A test's patience is the machine's, not a person's

A test asserting what a language server *says* SHALL be given a timeout scaled
to the machine — `Patience.seconds` — and SHALL NOT inherit a timeout chosen for
somebody at a keyboard.

A request whose default deadline exists for the interface SHALL let a caller
state its own, so that the app keeps the short one and the suite gets the
patient one.

#### Scenario: Signature help inside a full suite

- **GIVEN** a request whose default deadline is a keystroke's worth
- **WHEN** a test asks it for content
- **THEN** the test passes its own patient timeout
- **AND** the app's default is unchanged

