## 1. A capsule that fits

- [x] 1.1 Give `TitlebarCapsule` a `maximumWidth` and clamp
      `intrinsicContentSize` to it. Verify by photograph that
      `admin-user-service` on `fix/dev-user-service-memory-limit` shows a capsule
      where it showed none.
- [x] 1.2 Shorten the branch from the middle to whatever the project half leaves,
      and the name to a share of the capsule. Verify by photograph that the
      branch reads `fix/dev-us…ory-limit` rather than being cut at the end.
- [x] 1.3 Draw the shortened strings rather than the full ones, so what is
      measured and what is drawn agree. Verify by photograph that nothing is
      clipped at the capsule's edge.
- [x] 1.4 Confirm no regression for a name and branch that already fit: verify by
      photograph that `git-repo` on `main` is drawn in full, as before.

## 2. Finishing

- [x] 2.1 `make test` — 3630 tests, 25 issues (2 known), the same two failures
      as the baseline: `everyKindOfDiagramIsAPictureAndNotAProgram` (22 mermaid
      cases) and `theOlderPerConfigurationLockFilesAreReadToo`, which reads the
      machine's real `~/.gradle/caches`.
- [x] 2.2 `make warnings` — 2 warnings, both
      `Sources/AbydosApp/Navigator/SidebarController.swift:340` and `:351`, a
      file this change does not touch. **Taken on a wiped `build/warnings`**: see
      3.1 for why a warm one cannot be trusted.
- [x] 2.3 Keep `EditorViewController.swift` at its recorded 4394 lines. The size
      gate caught it at 4399 — five lines added to a file already over the
      1100-line limit — and the comment was tightened rather than the ceiling
      raised.
- [x] 2.4 Build only with a throwaway bundle identifier and an unpinned UUID, run
      the binary directly, never `make install`, and drive against a copy of the
      repository under the scratchpad rather than the reporter's own checkout.
