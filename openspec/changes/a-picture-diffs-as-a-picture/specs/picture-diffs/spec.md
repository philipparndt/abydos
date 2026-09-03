# Picture Diffs

## Purpose

What a changed picture shows wherever the app shows a diff. A picture is
binary to git and diffs as one line of prose; here it diffs as two pictures,
looked at in one of three ways.

## ADDED Requirements

### Requirement: A changed picture diffs as two pictures

A changed file the app recognises as a picture SHALL be shown as its two sides
read from git wherever a diff is shown — the commit page for a working-copy or
staged change, the log page for a commit, the pull-request page for a fetched
commit — fitted to the pane at one scale on a checkerboard, and SHALL NOT be
shown as the sentence a patch with no hunks gets.

The old side of an unstaged change is the file at `HEAD`; of a staged change,
the file in the index. The new side of an unstaged change is the working file;
of a staged change, the index. On the log page the two sides are the commit's
parent and the commit. Each side SHALL be labelled with what it is and its
size in pixels.

#### Scenario: a screenshot re-taken

- **GIVEN** `docs/images/editor.png` changed in the working copy
- **WHEN** its row is selected on the commit page
- **THEN** the detail shows the picture at `HEAD` and the working file, each labelled with its pixel size

#### Scenario: a picture in a commit

- **GIVEN** a commit that changed `icon.png`
- **WHEN** the file is selected on the log page
- **THEN** the detail shows the picture in the parent and in the commit

#### Scenario: a picture the app cannot decode

- **GIVEN** a changed picture whose bytes ImageIO will not decode
- **THEN** that side reads *cannot be read* and the other side still draws

### Requirement: Three ways of looking, and a switch between them

The picture diff SHALL offer three modes on a choice control above the
pictures — *Side by side*, *Slider*, *Changes* — and SHALL remember the mode
chosen as a setting, so the diff opens on it next time.

*Side by side* SHALL draw the old picture on the left and the new on the right
at one scale. *Slider* SHALL draw the two over each other at one scale with a
divider that starts in the middle and is dragged left and right, the old
picture showing to its left and the new to its right. *Changes* SHALL draw the
new picture with the regions that differ from the old outlined and the rest
dimmed, and SHALL say how many regions there are.

#### Scenario: switching to the slider

- **GIVEN** a changed picture shown side by side
- **WHEN** *Slider* is chosen
- **THEN** one picture is shown with a divider in the middle, the old side to its left, and the next picture diff opens on *Slider*

#### Scenario: dragging the divider

- **GIVEN** the slider
- **WHEN** the divider is dragged towards the right edge
- **THEN** more of the old picture shows and the divider stays where it was left through a resize of the pane

#### Scenario: the changed regions

- **GIVEN** two pictures of one size that differ in two places
- **WHEN** *Changes* is chosen
- **THEN** two outlined regions are drawn over the new picture and the caption says 2 regions

### Requirement: The regions are arithmetic on two bitmaps

Comparing two pictures SHALL be a function in AbydosKit over two bitmaps of
the same pixel size that yields the rectangles where they differ, testable
without a window. A pixel SHALL count as changed when any channel differs by
more than a small threshold, so a re-encode's rounding is not a change.
Differing pixels SHALL be gathered into rectangles by cells rather than
reported one by one. Pictures of different sizes SHALL yield no regions and a
reason, and pictures above a bound in pixels SHALL be declined with a reason;
the other two modes SHALL still draw them.

#### Scenario: identical pictures

- **WHEN** a picture is compared with a copy of itself
- **THEN** there are no regions

#### Scenario: one pixel changed by one

- **WHEN** one channel of one pixel differs by 1
- **THEN** there are no regions, because the threshold is what tells an edit from a re-encode

#### Scenario: two separate edits

- **WHEN** two pictures differ in two areas well apart
- **THEN** there are two regions, each covering its area

#### Scenario: different sizes

- **WHEN** a 640×480 picture is compared with a 1280×960 one
- **THEN** there are no regions and the reason names the two sizes

### Requirement: A picture with one side says so

An added picture SHALL show its new side only and a deleted picture its old
side only, the missing side labelled *no picture*; *Slider* and *Changes*
SHALL be unavailable for it and the switch SHALL say why.

#### Scenario: a new icon

- **GIVEN** an untracked `icon.png` on the commit page
- **THEN** the detail shows it on the right with *no picture* on the left, and only *Side by side* can be chosen
