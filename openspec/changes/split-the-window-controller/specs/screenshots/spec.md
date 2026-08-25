# screenshots

## ADDED Requirements

### Requirement: A driving verb is declared beside what it drives

A verb that exists to drive the app SHALL be declared on the type whose state
it reaches, and not on whichever type the flag that reaches it happens to
arrive at.

The flag arrives at the window controller because that is where a window is
opened, and for a long time the verb stayed where the flag landed. That is how
`MainWindowController` came to hold 193 members named `…ForTesting` — 3,749
lines, 28% of the file — of which 149, some 2,575 lines, touch nothing at all
but the sub-controller they forward to. `editorTextForTesting` is the editor's
business, `breakpointReportForTesting` is the debugger's, and neither is the
window's; they were merely reachable from there.

The cost is not that the verbs exist. Driving the real app is how anything in
`AbydosApp` is checked at all, and that is what this capability is for. The
cost is that a verb declared away from its subject has to be handed the
subject's private state to do its work, so the driving surface is the reason
the state cannot be made private — the test surface holding the design open.

So a driving verb goes where its state is, and the window controller forwards
to it or, better, the flag dispatch reaches the collaborator directly. When
state moves to a new collaborator, the verbs that read it move with it in the
same change, rather than being left behind pointing back in.

#### Scenario: a driving verb that reads one sub-controller

- **GIVEN** a verb whose body touches only the editor
- **WHEN** it is looked for
- **THEN** it is declared on the editor's own type

#### Scenario: state moving to a new collaborator

- **GIVEN** a driving verb that reads state which is being extracted into a
  collaborator of its own
- **WHEN** that extraction is made
- **THEN** the verb moves with the state in the same change, and no property
  is widened from `private` to keep the verb where it was

#### Scenario: a flag still doing what it did

- **GIVEN** any launch flag that drove the app before its verb was moved
- **WHEN** it is passed to a driven run afterwards
- **THEN** the run does what it did before, and prints what it printed before
