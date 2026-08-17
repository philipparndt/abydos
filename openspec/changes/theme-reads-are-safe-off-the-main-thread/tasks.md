## 1. Establish the access pattern, before changing anything

- [ ] 1.1 List every reader of `Theme.current` and say, for each, which thread it can
      run on. Most drawing code in `AbydosApp` reads it, so this is the real work.
- [ ] 1.2 List every writer — theme switching, any appearance-change observer — and
      the thread each runs on.
- [ ] 1.3 State plainly whether a torn read is reachable. If it is not, the hypothesis
      is dead: write that down with the evidence in the item and stop, rather than
      inventing a fix.

## 2. If the torn read is reachable

- [ ] 2.1 Choose between a boxed palette assigned as one reference and `@MainActor`
      on the property. Prefer confinement over a lock: the palette is read per row of
      a table, and this is an editor.
- [ ] 2.2 Implement it, and say in a comment which report it came from and what was
      eliminated on the way — the four empirical eliminations and the font-size one
      are the reason this candidate was pursued.
- [ ] 2.3 A test that a reader observes a whole palette across a switch. It cannot
      assert the crash is gone; say so where it is written, so nobody later reads it
      as proof.

## 3. Make the next report cheaper

- [ ] 3.1 Confirm the app's handler writes a symbolicated stack to
      `~/Library/Logs/Abydos/crash.log`, and correct the item's earlier note claiming
      the log is never reached — it is where the useful copy was found.
- [ ] 3.2 If the frames are still approximate, say what would have to change for the
      handler to name the function.

## 4. Finish

- [ ] 4.1 `make test` and `make warnings` both clean.
- [ ] 4.2 Write down what was ruled out on the way, keeping the existing eliminations
      rather than restating them from scratch.
- [ ] 4.3 Say whether the target's Swift language mode is now worth an argument of its
      own. Strict concurrency checking would surface this whole class, and if this
      investigation makes that case, it is a separate proposal and not this one.
- [ ] 4.4 If the hypothesis was disproved, the item goes back to waiting with the
      candidate list one shorter — that is a result, not a failure.
