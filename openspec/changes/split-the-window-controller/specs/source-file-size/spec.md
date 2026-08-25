# source-file-size

## ADDED Requirements

### Requirement: No source file is longer than a thousand lines

A Swift source file in `Sources` SHALL be no longer than 1,000 lines.

The number is a round one and it is not the point. The point is that a file
which cannot be held in mind stops being read and starts being appended to,
and the file that made this rule shows what that looks like: 13,030 lines,
674 members in one `final class`, and a `// MARK` section titled **Zoom**
holding 1,576 lines of sidebar tools, git pages and driving verbs. Nobody
decided that section should contain those things. It is where the cursor was.

A ceiling is worth having only if it is arithmetic rather than taste, so this
one is checked and not merely stated.

It is a limit on the *file*, which is the unit somebody opens. Where a type
genuinely wants more than a thousand lines, what it wants is collaborators
that own their own state — not the same state spread over more files.

#### Scenario: a file under the ceiling

- **GIVEN** a Swift file in `Sources` of 1,000 lines or fewer
- **WHEN** the check runs
- **THEN** it says nothing about that file

#### Scenario: a new file arriving over the ceiling

- **GIVEN** a Swift file in `Sources` of more than 1,000 lines that is not on
  the recorded list
- **WHEN** the check runs
- **THEN** it names the file and its length, and fails

### Requirement: What is already over the line is recorded, and may only get shorter

The files already over the ceiling SHALL be recorded by name and length, and
the check SHALL fail when one of them grows.

Twenty-seven files in `Sources` are over the ceiling on the day this is
written, 71,296 lines between them and 44,296 lines of excess. A check that
failed on all of them would be switched off within the hour, and a rule that is
switched off is worse than one that was never written: it teaches that the
checks in this repository are advisory.

So the list is the debt, written down. A file on it may shrink freely and may
be removed from the list when it comes under the ceiling. It SHALL NOT grow,
and it SHALL NOT be put back on the list once removed. An entry SHALL carry the
length it was recorded at, so that the direction of travel is visible in a
diff rather than inferred.

The list is empty when the work is done, and at that point the check needs no
list at all.

#### Scenario: a recorded file getting shorter

- **GIVEN** a file recorded at 4,051 lines
- **WHEN** it is 3,600 lines and the check runs
- **THEN** the check passes

#### Scenario: a recorded file getting longer

- **GIVEN** a file recorded at 4,051 lines
- **WHEN** it is 4,100 lines and the check runs
- **THEN** the check names the file, both lengths, and fails

#### Scenario: a recorded file coming under the ceiling

- **GIVEN** a file recorded at 1,020 lines
- **WHEN** it is 980 lines and the check runs
- **THEN** the check says the file may be struck from the list

### Requirement: The check runs with the other things said about the repository

The size check SHALL run under `make warnings` and SHALL report every file at
fault in one run.

`make warnings` is already the verb that says what is wrong with this
repository rather than with a build, and it is separate from `make build` for
the reason recorded there: an incremental build reports only the files it
recompiled, so a complaint is seen once by whoever happened to be watching and
then never again. A size check has exactly that failure mode and belongs on
exactly that side of the line.

Stopping at the first file at fault would turn one long job into as many runs
as there are files, so the check SHALL say everything it found, sorted by how
far over each file is, and SHALL exit non-zero if it found anything.

#### Scenario: several files at fault at once

- **GIVEN** three files over the ceiling and not on the list
- **WHEN** `make warnings` runs
- **THEN** all three are named, longest excess first, and the run exits
  non-zero

#### Scenario: nothing at fault

- **GIVEN** every file under the ceiling or unchanged on the list
- **WHEN** `make warnings` runs
- **THEN** the size check adds nothing to the output and does not change the
  exit code
