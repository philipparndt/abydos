## ADDED Requirements

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
