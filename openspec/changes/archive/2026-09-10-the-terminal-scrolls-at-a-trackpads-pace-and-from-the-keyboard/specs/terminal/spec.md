# Terminal

## ADDED Requirements

### Requirement: A trackpad scrolls a program by the distance the fingers moved

The terminal SHALL send a program, for a device reporting precise deltas, one
step per whole cell height the gesture has covered, accumulated across events,
with the fraction carried into the next event — whenever a wheel event is turned
into something for the program, which is wheel reports for a program tracking
the mouse and arrow keys for one on the alternate screen. A gesture that begins, or that
reverses direction, SHALL start with nothing carried. A device that does not
report precise deltas — a mouse wheel — SHALL be sent what it is sent today: one
step per event for a notch, more for a spun wheel, five at most.

Reported 2026-09-10: the terminal scrolled far too fast under a trackpad, and not
at all too fast under a mouse. Every trackpad event was at least one line
however small its delta, at a hundred events a second.

#### Scenario: a slow drag of one cell

- **GIVEN** a program on the alternate screen and a cell sixteen points tall
- **WHEN** a precise device raises ten events of two points each, downwards
- **THEN** the program is sent one arrow key, after the eighth event, and
  four points are carried

#### Scenario: a flick

- **GIVEN** the same program
- **WHEN** a precise device raises one event of one hundred points
- **THEN** the program is sent six arrow keys, and four points are carried

#### Scenario: the fingers reverse

- **GIVEN** fourteen points carried downwards
- **WHEN** an event of two points arrives upwards
- **THEN** nothing is sent and two points are carried upwards, not twelve
  downwards

#### Scenario: a wheel notch, as before

- **GIVEN** a program tracking the mouse
- **WHEN** a device without precise deltas raises one event of ten points
- **THEN** the program is sent one wheel report, as it was

### Requirement: The scrollback can be read from the keyboard

On the normal screen, ⇧⇞ and ⇧⇟ SHALL move the view a page up and down through
history, and ⇧Home and ⇧End SHALL move it to the oldest line and back to the
prompt, without sending the program anything. ⇧End SHALL pin the view to the
bottom again so output follows as it did. On the alternate screen these keys
SHALL reach the program exactly as they do today, and the unshifted keys SHALL
reach the program on either screen.

#### Scenario: paging back through a long build log

- **GIVEN** a shell whose output is longer than the pane
- **WHEN** ⇧⇞ is pressed
- **THEN** the view moves up by one pane height, less one row, and the program
  receives nothing

#### Scenario: back to the prompt

- **GIVEN** the view scrolled into history
- **WHEN** ⇧End is pressed
- **THEN** the view is at the bottom, and the next line of output keeps it
  there

#### Scenario: a full-screen program

- **GIVEN** `less` on the alternate screen
- **WHEN** ⇧⇞ is pressed
- **THEN** `less` receives what it received before this change
