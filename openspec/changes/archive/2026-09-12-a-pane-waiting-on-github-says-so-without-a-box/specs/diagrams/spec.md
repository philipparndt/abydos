# Diagrams

## MODIFIED Requirements

### Requirement: A pane with no diagram in it says why, and the indicator stays clear of what it says

A pane with no diagram in it SHALL say why, and the indicator SHALL stay clear of what it says.

A diagram pane is a picture or it is a sentence. There is no picture while a
tool is being run, none for a file with nothing drawable in it yet, and none for
a diagram the tool refuses — so the pane says what is happening or what is
wrong, in the middle. What turns while a tool runs is the waiting strip every
pane has, at the pane's top edge, which is nowhere near the message.

The message is **wrapped, not elided**: what it says is a sentence somebody
wrote to be read — what to install, what the parser expected and on which line —
and the middle of such a sentence is usually the part worth having. So it may be
several lines, centred in the pane on its own, and no length of message and no
width of pane can put the strip inside the text.

A tool run over a picture still on screen shows the strip alone, and the
picture stays until the new one replaces it.

#### Scenario: a message long enough to wrap while a tool is running

- **Given** a diagram being drawn, in a pane narrow enough that what the pane is
  saying takes more than one line
- **When** it is looked at
- **Then** the message is shown whole, over as many lines as it needs, and the
  strip sweeps at the top edge, clear of the letters

#### Scenario: a diagram the tool will not draw

- **Given** a file whose diagram does not parse
- **When** the tool answers
- **Then** the pane shows what it said, centred in the pane, with nothing
  sweeping at the top edge and no gap where something turning would have been
