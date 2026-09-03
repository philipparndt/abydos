# theme-access Specification

## Purpose
TBD - created by archiving change theme-reads-are-safe-off-the-main-thread. Update Purpose after archive.
## Requirements
### Requirement: The palette is read and written on the main thread only

`Theme.current` SHALL be read and written on the main thread and nowhere else.
Assigning one is not a single store — it is a struct of some thirty-five
`NSColor`s and two further fields — so a reader that caught it mid-assignment
would get a palette belonging to neither, which is the shape of the abort in
0400: rare, unreproducible by probing the values, and invisible in the source at
the crash site.

The audit that established this is recorded with the change. **An audit is true
on the day it is done**, and this one is a claim about 1580 reads across 99
files, so it SHALL be kept true by a check that runs rather than by anybody
remembering it: a debug build SHALL record a read or a write from any other
thread, and SHALL say so once rather than once per read.

The check SHALL cost nothing in a release build.

#### Scenario: the app running normally

- **GIVEN** a debug build with a project, a terminal and the panel open
- **WHEN** it is driven and then asked what it saw
- **THEN** it reports that the palette was touched on the main thread only

#### Scenario: the palette changing under everything that draws

- **GIVEN** the same build
- **WHEN** the appearance is switched five times while the window redraws
- **THEN** it still reports the main thread only

#### Scenario: something reads it from elsewhere

- **GIVEN** a debug build in which some code reads the palette off the main
  thread
- **WHEN** that code runs
- **THEN** one line naming the thread and the stack is written to standard error
- **AND** the run's report says how many such reads and writes there were

### Requirement: A crash log carries what its addresses need to be read

The crash log SHALL carry, beside the frames, the build it came from, the address
the image was loaded at and the image's UUID. `callStackSymbols` resolves through
`dladdr`, which sees exported symbols only — for an optimised Swift binary that
is frequently a function nowhere near the crash. 0400's report named
`showConfigurationMenu` and `stopDevPodForwards` and both were wrong; what named
the real site was the breadcrumb the app writes before it measures text, not the
stack. Without those the
addresses in an old log cannot be turned into anything: ASLR puts the image
somewhere different every launch, and the UUID is what says which dSYM answers
for it.

#### Scenario: an uncaught exception

- **WHEN** one is raised and the handler writes the log
- **THEN** the log names the build, the load address, the slide and the UUID
- **AND** it names what was last being drawn, before the frames

### Requirement: A value copied out of the theme is re-taken when the theme changes
A colour, a font or a metric read from `Theme.current` and stored — in a layer, in a control, in a constraint constant or in a row height — SHALL be re-read when the palette or the scale changes. A view that reads the theme inside its drawing satisfies this by repainting; a view that copies the value SHALL have a path that copies it again.

#### Scenario: A metric captured when a view was built
- **WHEN** a view stores a scaled metric at build time and the scale later changes
- **THEN** the stored metric is recomputed at the new scale before the view is next shown

#### Scenario: A colour copied into a control
- **WHEN** a control is given a colour from the palette and the palette later changes
- **THEN** the control is given the corresponding colour from the new palette

