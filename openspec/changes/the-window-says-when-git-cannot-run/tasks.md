## 1. The fact, in AbydosKit

- [x] 1.1 `GitAvailability` in `Sources/AbydosKit/Git`: `Cause`
      (`licenceNotAccepted`, `developerToolsMissing`) with its sentence and
      its command; `classify(_:)` over stderr; `shared` with `isRunning`,
      `cause`, `note(_:)` and an observer list; `--git-unavailable` honoured
      through a `forcedCause`.
- [x] 1.2 `GitRepository.run` and `GitBlob` note every result before answering.
- [x] 1.3 `GitAvailabilityTests`: the two sentences as the shim prints them
      classify; `fatal: not a git repository` at exit 128 does not; a success
      after a refusal answers running again and tells the observer once.

## 2. The window

- [x] 2.1 `GitAvailabilityBanner` beside `TrustBanner`: the sentence, the
      command in monospace, *Copy Command* onto the pasteboard, no close.
- [x] 2.2 Hung where the trust strip is; `updateTopInsets` and the height
      constraints treat "a strip is up" as either; when both would show, this
      one does and the trust strip waits.
- [x] 2.3 `load(project:)` notes the remote only while git is running; when
      availability comes back the window re-asks its project's remote and
      refreshes the trust strip.
- [x] 2.4 `applicationDidBecomeActive`: one `git --version` while the strip is
      up.

## 3. Proving it

- [x] 3.1 `--git-unavailable licence|tools`; `--trust-report` prints
      `GIT: strip=[…]`.
- [x] 3.2 Driven on a scratch repository whose `origin` names a trusted host,
      built as `de.rnd7.abydos.gitshim` with an unpinned UUID: with
      `--git-unavailable licence` the strip's text and `trusted=false
      banner=[]`; without it `trusted=true` and no strip. Recorded in the
      design under a dated heading.

## 4. Before finishing

- [x] 4.1 One `##` in `docs/release-notes-0.21.1.md`, in the shape of 0.20.6.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate the-window-says-when-git-cannot-run`.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `project-trust` is what this
change amends and `git-availability` is what it adds.
