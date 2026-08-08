# Return after an opening brace writes the closing one

`4894f906e` · 2026-08-06

Return already indented the body of a block and already split a pair the caret
sat between. What it would not do is finish a block that had only been opened
— type `{`, press return, and the closing brace was yours to remember, one
line down and one level out.

It writes it now, and waits on the blank line between the halves. Only when
the file actually needs one: the document is counted first, so a `{` typed
inside an already-balanced block does not gain a `}` that nothing closes. An
editor that adds a brace nobody asked for is worse than one that adds none.

A colon still writes nothing, since that is how Python opens a block and it
closes with nothing at all.

Also, the typing harness presses return rather than inserting a newline
character. Inserted directly it skipped everything return does, so a test that
typed one was testing something nobody does — which is why this behaviour
looked fine while being absent.
