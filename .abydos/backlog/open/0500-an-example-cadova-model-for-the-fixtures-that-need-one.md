# 500. An example Cadova model, for the fixtures that need one

0424 made the examples repository the fixture for anything that cannot be
tested by reasoning, and eighteen `*LiveTests` use it: `ExampleProjects.root`
finds `../abydos-examples` beside this checkout — or three levels further up,
when the caller is in a worktree — and every test using it skips cleanly when
it is not there.

0498 and 0499 both want one of these. Discovering a Swift package's executables
and previewing what one of them writes are exactly the claims that cannot be
argued, only run.

## What it has to be

A Swift package depending on Cadova, with at least one executable target that
writes a 3MF. The hex key holder from Cadova's own README compiles unmodified
and is a reasonable size — measured in the 0499 spike: 22s to resolve, 46s to
build cold, ~2s warm, and a 3MF with 460 vertices and 916 triangles.

Two targets rather than one would be worth it, so 0498's discovery has
something to disagree about.

## Worth deciding

- **Whether it is checked in built or built by the test.** A cold build is 46
  seconds and pulls seven packages from the network. That is fine for a live
  test that skips when the repository is absent, and it is *not* fine anywhere
  it could land in the ordinary suite. Keep it on the skipping side of that
  line, the way the container tests are.
- **Version pinning.** Cadova is pre-release below 1.0 and says the API moves
  between minor versions; it recommends `upToNextMinor`. An example that stops
  compiling in six months is worse than no example, so the manifest should pin
  and `Package.resolved` should be committed.
- **Which repository the item is done in.** The example lives in
  `abydos-examples`, which is a different checkout with its own history. This
  item's commits are mostly not in this repository, and it should say so
  plainly when it is finished.

## Steps

- [ ] A Cadova package in `abydos-examples`, pinned, with `Package.resolved`
      committed, and more than one executable target
- [ ] It builds and writes a 3MF from a clean checkout
- [ ] A live test that uses it and skips cleanly when the examples repository
      is not beside this one
- [ ] Say in the item which commits are in which repository
- [ ] Write down here what was ruled out on the way
- [ ] The spec, if this changes what the project does — it may not, and saying
      so is the answer rather than skipping the step
