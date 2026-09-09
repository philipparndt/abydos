## MODIFIED Requirements

### Requirement: A change cannot be dragged between columns

Dragging SHALL be refused for a change's card, and the refusal SHALL say why
rather than the card simply not moving. A backlog item drags because moving its
file is what changing its state means; a change's column is read out of its files,
so a drag could only mean rewriting checkboxes nobody opened.

A box ticked in the card's task tip is not that rewrite. The tip lists each
open task by its words, and the click lands on the one task it ticks, so the
person has read what they are ticking; a drag names a column, and which boxes
would get it there is nobody's decision. The refusal SHALL point at the tip as
well as at the file: tick the tasks on the card, or in `tasks.md`, and the card
follows.

#### Scenario: dragging a change

- **GIVEN** a change's card in Ready
- **WHEN** it is dragged towards In progress
- **THEN** it does not move, and the pane says a change's state comes from its
  tasks, which can be ticked on the card or in `tasks.md`

#### Scenario: backlog cards still drag

- **GIVEN** the same pane switched to the backlog
- **WHEN** an item is dragged from Ready to In progress
- **THEN** it moves, exactly as it does today
