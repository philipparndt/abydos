# Sessions — delta

## ADDED Requirements

### Requirement: A message being composed survives leaving the project

A project's session SHALL carry the commit message being composed — the summary
and the description both — and SHALL put it back when the project is returned to.

It SHALL be put back wherever the message is composed: the sidebar's changes
pane or the commit page, whichever the returning window builds. It SHALL be put
back where the field is empty and SHALL NOT overwrite anything typed since —
what somebody has just typed is the more recent statement, which is the rule
drafting already follows.

Restoring SHALL survive the sidebar tool being rebuilt when the repository
finishes loading, which happens a second or two after a window opens and is a
second door onto the same loss: the code that rebuilds it already records having
taken "the commit message half typed into the pane" with it.

A commit message is the most expensive text in the app to lose. It is written
once, from a diff somebody has just read, and typing it again means reading the
diff again. The description is the half that says *why* and the half that is
expensive, so carrying only the summary is not carrying the message.

#### Scenario: switching away mid-message

- **GIVEN** a summary and a description typed and not committed
- **WHEN** another project is opened and the first returned to
- **THEN** both fields hold what was typed

#### Scenario: the repository finishes loading underneath

- **GIVEN** a message typed into the changes pane
- **WHEN** reading the repository rebuilds the sidebar tool
- **THEN** the message is still there

#### Scenario: something typed since

- **GIVEN** a session holding a message, and a summary typed into the returning
  pane before the restore lands
- **THEN** what was typed stands, and the session's message does not replace it

#### Scenario: a committed message

- **GIVEN** a message that has been committed and the fields cleared
- **WHEN** the project is left and returned to
- **THEN** the fields are empty

### Requirement: The pages a window had are part of its session

A project's session SHALL carry the pages that were open — commit, log, stash,
and the pages whose identity is their identifier alone — and SHALL reopen them
when the project is returned to.

A page was excluded from a session on the argument that "a path like
`/ideai/page/launch` is nothing to reopen". That is true of the synthetic URL and
false of the page: it is a view over a repository with a scope and a selection,
and it was opened on purpose.

A page SHALL be reopened only once the repository is ready. Every opener refuses
while the project's git is still unread, so reopening earlier would drop the
restore silently.

A session that says nothing about pages SHALL open none: a project opened for the
first time behaves as it did before this requirement.

#### Scenario: pages open at the switch

- **GIVEN** a log page and a commit page open
- **WHEN** another project is opened and the first returned to
- **THEN** both pages are open again

#### Scenario: a project with no recorded pages

- **GIVEN** a project whose session names no pages
- **THEN** no page is opened
