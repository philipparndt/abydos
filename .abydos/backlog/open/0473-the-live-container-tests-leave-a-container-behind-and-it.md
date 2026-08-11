# 473. The live container tests leave a container behind, and it breaks the next run

`ContainerLSPLiveTests` leaks a container per run. Three separate agents reported
it today as an aside — "cleaned up the ones my runs left but did not fix the leak"
— and it was treated as untidiness. **It is not untidiness. It fails the suite.**

Measured today, on one commit:

- With `abydos-lsp-jdtls-75631-23` left behind by a test process that had died
  two hours earlier, `aServerInAContainerAnswersAboutFilesOnThisMachine` failed
  its jdtls case on `diagnosed.uri == fileURI` — **twice in a row** — and the
  suite took **124 s** instead of 31.
- The same container removed, nothing else changed: the suite passed in 56 s, and
  passed again afterwards.

So a stale container of the same tool does not merely take memory: something finds
it and answers about the wrong paths. Whether that is the app's own reuse-by-name
or the runtime handing back an old one is the first thing to find out, and it may
be a **bug in the reuse rather than in the tests** — which would make this an item
about the app and not about hygiene.

## What is known about the sweep

There is already a sweep, and it works — one agent saw the app print `Removed 4
container(s) left by an earlier run`. But it spares containers whose owning
process is still alive, which is right, and that is why four of them survived
today: `abydos-lsp-jdtls-{53519,64145,66987}-23` started between 14:29 and 14:34
by processes that were still running. The names carry the owning pid, so the rule
is sound and the leak is that a *finished test run* does not clean up after
itself before its process exits.

## Why it is worth fixing rather than living with

Every one of today's five agents had to reason about container state, and two of
them lost time to a red suite that was not theirs. A leak that only costs disk can
wait; a leak that makes a different test fail teaches everybody to distrust the
suite, which is the expensive kind of failure.

## Worth deciding

- **Where the cleanup belongs** — a suite-level teardown, a `deinit`, or the
  existing sweep made to run at the *start* of a live-container test rather than
  at app launch. The last one is the smallest and covers a crashed run too, which
  a teardown cannot.
- **Whether the URI failure is the tests' fault at all.** If the app reuses a
  container by name and gets one from a dead process, the sweep is a workaround
  for a reuse bug. Find out before choosing where the cleanup goes.
- **What a leaked container costs when nothing fails**, so the sweep's own
  reporting says something useful — four of them is 4 GB of the runtime's memory
  by the figures in `container ls`.

## Steps

- [ ] Reproduce it deliberately: leave a container, run the suite, watch the
      jdtls case fail
- [ ] Find out whether the failure is reuse-by-name or the runtime, and say which
- [ ] Clean up where a crashed run is covered too, not only a tidy exit
- [ ] The suite green with a stale container present
- [ ] Write down here what was ruled out on the way
- [ ] `spec/tool-images.md` says what the project now does, if the reuse changed
