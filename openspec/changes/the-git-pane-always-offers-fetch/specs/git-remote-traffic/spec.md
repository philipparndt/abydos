## ADDED Requirements

### Requirement: Fetching is one press away in every state
The git pane SHALL offer a control that fetches from the remote, titled with the word `Fetch`, whenever the repository has a remote — whatever the branch's state relative to its upstream. The control SHALL NOT be a glyph whose meaning is carried only by a tooltip.

#### Scenario: A branch that is ahead
- **WHEN** the branch is ahead of its upstream, so the row's own verb reads `Push`
- **THEN** a control titled `Fetch` is on the row as well, and pressing it fetches

#### Scenario: A branch that is level
- **WHEN** the branch is level with its upstream, so the row's verb also reads `Fetch`
- **THEN** the `Fetch` control is still shown, because it is always shown, and either target fetches

#### Scenario: No remote
- **WHEN** the repository has no remote
- **THEN** no `Fetch` control is drawn, because there is nowhere to fetch from, and re-reading the repository remains on the row's context menu

## REMOVED Requirements

### Requirement: The repository row offers a local re-read
**Reason**: The glyph that offered it already fetched where there was a remote, and re-read only what the pane's own filesystem watcher re-reads on every event. A control meaning two different things depending on state is why it was unreadable.
**Migration**: Re-reading the repository is on the repository row's context menu.
