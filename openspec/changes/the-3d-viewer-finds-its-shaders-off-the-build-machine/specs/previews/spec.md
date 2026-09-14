# Previews

## ADDED Requirements

### Requirement: A model opens on a machine that did not build the app

The 3D viewer SHALL find its shader bundle inside the application bundle it
ships in, and SHALL NOT depend on the build directory of the machine that built
it. When the bundle cannot be found the viewer SHALL show no model and say that
its resources are missing, in the place a render failure is reported, and the
process SHALL NOT end.

Reported 2026-09-14: Abydos 0.21.0 died with `EXC_BREAKPOINT` in SwiftPM's
generated `Bundle.module` the first time a model was opened, because the
installed binary looked for `GoSTL_GoSTL.bundle` at the `.app` root and then at
`/Users/philipparndt/dev/abydos/.build/…`, and neither exists anywhere but the
machine that built the release.

#### Scenario: an installed release

- **GIVEN** a release built on one machine and installed on another
- **WHEN** an `.stl` is opened
- **THEN** the model is drawn

#### Scenario: the build directory's copy is gone

- **GIVEN** a build on this machine with `.build/<arch>/release/GoSTL_GoSTL.bundle`
  moved aside
- **WHEN** a model is opened in a driven run and a Metal shot taken
- **THEN** the shot shows the model, and the run ends by itself

#### Scenario: a build with no bundle at all

- **GIVEN** the same, with the app's `Contents/Resources/GoSTL_GoSTL.bundle`
  moved aside too
- **WHEN** a model is opened
- **THEN** the model half shows no shape, says the viewer's resources are
  missing from this build, and the app keeps running
