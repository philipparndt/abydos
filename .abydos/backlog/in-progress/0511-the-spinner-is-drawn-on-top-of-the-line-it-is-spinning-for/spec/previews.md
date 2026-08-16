## MODIFIED Requirement: A Cadova model is built and run to be seen

A Cadova model is not a file the viewer can open. It is an executable target in
a Swift package, and the shape exists only once the program has been built and
run: `swift run <product>` in the package root writes a 3MF beside the package,
and that is what the model half shows.

Two things follow that nothing else in the previews needs. **Where the file is
can only be learnt from the run**, because Cadova names it after the model
inside the code rather than after the target or the file, so the pane reads the
path out of what the run printed. And **a run takes seconds and can fail**, so
the pane says what it is doing while it does it, and a build that produces no
model shows what the compiler said in place of the model rather than a shape
that is not the one the code describes.

What the pane says while it builds is the build's own last line, so it is text
of no known length: it is shown **on one line, truncated in the middle**, with
the turning indicator **above** it rather than through it. The two are one
arrangement centred in the pane, so no length of line and no width of pane can
put them on top of each other — and when nothing is turning the line is centred
on its own, rather than held at an offset that only makes sense with something
above it.

Any of the target's sources counts, not only the file with the model in it:
running the target is what makes the shape, so a helper file changes it just as
much. Which means the pane rebuilds when any of them changes **on disk** — the
compiler reads the disk, so an unsaved buffer would show the shape of the last
save — with a burst of saves producing one rebuild rather than one each, and a
change arriving during a build honoured when that build ends. A build is never
killed to make way for a newer one: a half-stopped `swift build` leaves its
build directory inconsistent, and the next build of that package is a cold one.

The file is rewritten in place, so a rebuild that writes the same path leaves
the view of the model alone — turning the part round to look at what changed is
the work, and a viewer rebuilt from nothing would put the camera back.

### Scenario: opening one

- **Given** `Sources/spike/main.swift`, whose target depends on Cadova
- **When** it is opened
- **Then** the pane says it is building, naming the product, and shows what the
  build is saying while it runs
- **And** when the build finishes the model it wrote is shown beside the source

### Scenario: a build line longer than the pane is wide

- **Given** a Cadova model building in a narrow pane
- **When** the build prints a line too long to fit
- **Then** the line is shown on one line with its middle elided, and the turning
  indicator is clear above it rather than drawn over the letters

### Scenario: changing a constant

- **Given** that model on screen
- **When** a dimension in the source is changed and saved
- **Then** the target is built and run again, and the new shape replaces the old
  one without the view of it being reset

### Scenario: a build the compiler refuses

- **Given** that model on screen
- **When** the source is saved with an error in it
- **Then** the model is taken away and the compiler's own message is shown in
  its place, naming the file, the line and what is wrong
- **And** when the source is repaired and saved, the model comes back

### Scenario: nothing was written and nothing said `error:`

- **Given** a machine whose `swift` cannot build this package at all
- **When** the model is opened
- **Then** the pane shows what the run actually said, rather than reporting that
  no model appeared
