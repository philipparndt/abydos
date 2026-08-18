## 1. Establish the access pattern, before changing anything

- [x] 1.1 List every reader of `Theme.current` and say, for each, which thread it can
      run on. Most drawing code in `AbydosApp` reads it, so this is the real work.
- [x] 1.2 List every writer — theme switching, any appearance-change observer — and
      the thread each runs on.
- [x] 1.3 State plainly whether a torn read is reachable. If it is not, the hypothesis
      is dead: write that down with the evidence in the item and stop, rather than
      inventing a fix.

## 2. If the torn read is reachable — it is not

- [x] 2.1 **Not needed, and not invented.** 1.3 came back negative, so there was
      nothing to choose between: a fix for a race that cannot happen would be a
      cost on every read of the palette paid for a hypothesis that had just been
      disproved. What was built instead is the check that keeps the finding true.
- [x] 2.2 The comment on `Theme.current` and on `ThemeAccess` says which report
      this came from, what the audit found, and why a watcher rather than a lock.
- [x] 2.3 There is no behaviour to assert — the palette is not published
      differently. The claim that replaced it is observational and is asserted by
      driving: two runs, one of them switching the appearance five times while the
      window redrew, both reporting the main thread only.

## 3. Make the next report cheaper

- [x] 3.1 Confirm the app's handler writes a symbolicated stack to
      `~/Library/Logs/Abydos/crash.log`, and correct the item's earlier note claiming
      the log is never reached — it is where the useful copy was found.
- [x] 3.2 If the frames are still approximate, say what would have to change for the
      handler to name the function.

## 4. Finish

- [x] 4.1 `make test` and `make warnings` both clean.
- [x] 4.2 Write down what was ruled out on the way, keeping the existing eliminations
      rather than restating them from scratch.
- [x] 4.3 Say whether the target's Swift language mode is now worth an argument of its
      own. Strict concurrency checking would surface this whole class, and if this
      investigation makes that case, it is a separate proposal and not this one.
- [x] 4.4 If the hypothesis was disproved, the item goes back to waiting with the
      candidate list one shorter — that is a result, not a failure.
