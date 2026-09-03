## ADDED Requirements

### Requirement: The overflow control belongs on every strip

A strip SHALL draw its overflow control wherever it holds more tabs than it can
show, whether or not it also carries the panel's own controls. tmux's mirroring
strip and a torn-off terminal window's strip carry none of those, and a window
list that stops at the edge with nothing to say so is the fault this answers.

The control SHALL be drawn in the ink of the strip it is on, so that it reads as
part of tmux's bar on tmux's bar.

#### Scenario: sixteen tmux windows on a strip that fits seven

- **GIVEN** the mirroring strip with sixteen windows and room for seven
- **WHEN** it is drawn
- **THEN** the chevron is drawn at its trailing end saying nine are not shown
- **AND** opening it lists those nine, by tmux's own numbers

#### Scenario: choosing a window that was hidden

- **GIVEN** that list
- **WHEN** one is chosen
- **THEN** it becomes the active window
- **AND** the run moves the least that brings it wholly into view

#### Scenario: a torn-off terminal window

- **GIVEN** a torn-off window whose strip has more tabs than it can show
- **WHEN** it is drawn
- **THEN** the chevron is there too
