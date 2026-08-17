## ADDED Requirement: A pane with no diagram in it says why, and the indicator stays clear of what it says

A diagram pane is a picture or it is a sentence. There is no picture while a
tool is being run, none for a file with nothing drawable in it yet, and none for
a diagram the tool refuses — so the pane says what is happening or what is
wrong, in the middle, with the turning indicator above the message rather than
through it.

The message is **wrapped, not elided**: what it says is a sentence somebody
wrote to be read — what to install, what the parser expected and on which line —
and the middle of such a sentence is usually the part worth having. So it may be
several lines, and the two are one arrangement centred in the pane, so that no
length of message and no width of pane can put the indicator inside the text.

When nothing is turning the message is centred on its own. It is not held at an
offset that only makes sense with something above it: a pane showing a file with
nothing to draw, or a complaint about one, stays that way until somebody does
something about it, so a gap reserved for an indicator that is not there would
be on screen for the whole of the state it was reserved for.

### Scenario: a message long enough to wrap while a tool is running

- **Given** a diagram being drawn, in a pane narrow enough that what the pane is
  saying takes more than one line
- **When** it is looked at
- **Then** the message is shown whole, over as many lines as it needs, and the
  turning indicator is clear above it rather than drawn over the letters

### Scenario: a diagram the tool will not draw

- **Given** a file whose diagram does not parse
- **When** the tool answers
- **Then** the pane shows what it said, centred in the pane, with nothing
  turning above it and no gap where something turning would have been

### Scenario: a picture arrives

- **Given** any of the above
- **When** a drawing is produced
- **Then** the picture replaces the message rather than being drawn over it
