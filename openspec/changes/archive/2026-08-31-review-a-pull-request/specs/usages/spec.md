# usages

## ADDED Requirements

### Requirement: A tick may be recorded against the thing it was about

A checklist SHALL be able to record, per row, what the tick was made against,
and to clear the ticks whose subject has since changed while keeping the rest.

**Marking done is presently one-way**: a row is struck through until somebody
unstrikes it or the list is rebuilt. That is right for a usages list and for a
search, where the rows are answers to a question asked once and the question is
asked again from the beginning. It is wrong for a list of files in a pull
request, where the list stays and the *rows* change underneath it: a tick left
standing against a diff the author has since rewritten says a file has been
read when nobody has read it, and a checklist whose ticks cannot be trusted is
worse than no checklist, because it is believed.

So a tick may carry a token — for a pull request, the head commit and the file's
diff at that head — and the list may be told to keep the ticks whose token still
matches and clear the ones whose token does not. Nothing is invalidated unless a
token was given, which is the case the usages list and the search results are
in, and their behaviour is unchanged.

#### Scenario: a list that gives no token

- **GIVEN** a usages list, whose rows carry no token
- **WHEN** rows are marked done and the list is asked to revalidate
- **THEN** every tick is kept, as it is today

#### Scenario: some rows changed underneath the list

- **GIVEN** a checklist of four rows, all ticked, each carrying a token
- **WHEN** it is revalidated and one row's token differs
- **THEN** that row is unticked and the other three stay ticked

#### Scenario: what the count says afterwards

- **GIVEN** the same list after one tick has been cleared
- **WHEN** its progress is read
- **THEN** it says three of four, and hiding the done ones leaves the cleared
  row showing
