## 1. Which checkout holds it

- [ ] 1.1 A question answered from the worktree list: given a branch, which
      checkout has it — and nil when none has, which is every other refusal.
- [ ] 1.2 It tells apart the primary clone, a worktree, and a registration whose
      directory is gone. All three are already on `GitWorktree`.
- [ ] 1.3 Tests over the answer, including a detached worktree (which holds no
      branch), a branch name that is a prefix of another, and the branch the
      asking checkout is on itself.

## 2. The offer

- [ ] 2.1 A failed checkout asks the question, and where the answer is a live
      checkout the notification offers to open it.
- [ ] 2.2 The offer opens it through the door every other way of choosing a
      checkout uses — not a second implementation.
- [ ] 2.3 Where the answer is a missing directory, the offer is to prune, says
      the directory is gone, and does not retry the switch.
- [ ] 2.4 Where there is no answer, git's own message is shown exactly as today.
- [ ] 2.5 The sentences live where they can be read without a window.

## 3. Every way in

- [ ] 3.1 The titlebar menu and the project switcher, which already share one
      function.
- [ ] 3.2 The branches pane, which has its own.
- [ ] 3.3 One implementation between them, so the three cannot drift.

## 4. Watched

- [ ] 4.1 Against a scratchpad repository, never a real checkout: a worktree
      holding a branch, the branch chosen, the offer read, the offer taken, the
      window on that checkout.
- [ ] 4.2 The offer declined: nothing moved.
- [ ] 4.3 A branch held by the primary clone, named as the main checkout.
- [ ] 4.4 A worktree deleted with `rm -rf`: the prune offer, taken, and the
      branch free afterwards.
- [ ] 4.5 A dirty work tree: git's message, no offer.

## 5. Finish

- [ ] 5.1 `version-control` says what a held branch offers and what a stale
      registration offers instead. Name any sentence this makes untrue.
- [ ] 5.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 5.3 Write down what was ruled out on the way, and answer or restate the
      two questions the design leaves open.
