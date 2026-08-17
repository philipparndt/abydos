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

