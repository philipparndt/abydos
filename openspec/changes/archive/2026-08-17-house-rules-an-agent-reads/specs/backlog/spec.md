## ADDED Requirements

### Requirement: An agent the tool starts reads the house rules unprompted

An agent launched by `abydos-backlog start` SHALL have the repository's house rules
available to it without a person adding them to the prompt. The rules SHALL exist in
exactly one copy, and the prompt the tool builds SHALL NOT restate them.

`BacklogRunner.prompt(number:title:path:branch:)` is thin on purpose, and its comment
is right about why: repeating the workflow there would be a second copy that drifts,
and the drift would be invisible, because nobody reads the prompt a button builds. So
the rules cannot go in the prompt — but they have to be somewhere the prompt reaches,
or somewhere the assistant reads on its own.

Until 0464 the question did not arise: every agent was handed its item by a person who
also said how to behave on this machine. The tool starting them itself is what makes
this urgent rather than tidy.

#### Scenario: a throwaway item, started by the tool

- **Given** an agent started by `abydos-backlog start`, with nothing added to its
  prompt by hand
- **Then** it observes a rule it was not given — it builds with a throwaway bundle
  identifier, or can state the rule when asked
- **And** that rule appears in exactly one file

#### Scenario: the prompt stays thin

- **Given** a prompt built by `BacklogRunner.prompt`
- **Then** it names where the rules are, or relies on the assistant reading them
- **And** it does not contain a copy of them

#### Scenario: an agent the tool did not start

- **Given** an agent working in this repository that nobody launched through the
  backlog, which is most of them
- **Then** the same rules are reachable to it

### Requirement: A rule carries the failure that motivated it

Each house rule SHALL state what went wrong that caused it to be written, so that it
can be applied to a case the list does not mention.

This is the house style applied to prose rather than to code, and for the same
reason. "Never push" is obeyed; "never push, because an agent once created five public
Docker Hub repositories nobody asked for" is understood, and an understood rule
generalises.

#### Scenario: a rule is read

- **Given** the rule about never pushing or publishing
- **Then** it also says that an agent once created five public Docker Hub
  repositories that nobody asked for

#### Scenario: a rule is learnt

- **Given** an agent doing something that has to be forbidden afterwards
- **Then** the rule is written with what it cost, at the time, in the one file

### Requirement: What is true today is kept apart from what is permanent

Rules describing the state of this machine on a given day SHALL be recorded separately
from rules that are permanently true, and the temporary record SHALL say which day it
describes.

"Never push" is forever. "Docker is stopped because Apple containers are being tested"
is a Tuesday. A document mixing them teaches an agent to distrust all of it, and the
temporary half needs to be editable without a commit that reads like a policy change —
which a section heading does not give it.

#### Scenario: a fact about this machine today

- **Given** a container runtime deliberately stopped while another is tested
- **Then** that is recorded in the temporary place, not beside "never push"
- **And** changing it is not a commit that reads like a policy change

#### Scenario: the temporary record is read

- **Given** an agent reading the temporary record
- **Then** it is told that the contents describe a particular day, and which

### Requirement: The rules say which of them a program enforces

Where a rule is already kept by the program or by the suite, the document SHALL say
so, so that attention goes to the rules nothing enforces.

A rule with a guard behind it is one an agent can stop worrying about. A rule without
one is where the attention belongs, and a document that does not distinguish them
spends the same attention on both.

#### Scenario: a rule with a guard behind it

- **Given** the rule to use `TestDefaults.make()` rather than `UserDefaults(suiteName:)`
- **Then** it also says that `NamedSuiteTests` enforces it

#### Scenario: a rule with nothing behind it

- **Given** a rule that nothing enforces
- **Then** the document does not imply that anything does
