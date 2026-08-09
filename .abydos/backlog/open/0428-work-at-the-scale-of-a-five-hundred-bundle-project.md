# 428. Work at the scale of a five-hundred-bundle project

The app is to be used on a Java/RCP product at work: **around 500 Maven bundles
and 500,000 to 700,000 lines**. The goal is not "it opens" — it is that it feels
fast at that size. Nothing in this repository has ever been opened at that scale,
and every number in the performance suite comes from a synthetic 100,000-line
file rather than from a real project with half a million lines spread across
hundreds of modules.

So the first work is not optimisation. It is a corpus and a baseline, because
"ultra fast" without a number is an adjective.

## The corpus

**Eclipse Platform** is the near-exact match, and matters because it is the same
*shape* rather than merely the same line count: RCP, built with **Tycho** (Maven
for OSGi), hundreds of bundles by construction.
`eclipse-platform/eclipse.platform.ui` is a few hundred bundles on its own; with
JDT and PDE alongside it the aggregator is in the right order of magnitude.

- **Eclipse Papyrus** or **Sirius** — RCP and Tycho, smaller. The fast inner
  loop: if something is slow there it is hopeless on the Platform, and a
  measurement takes minutes rather than an afternoon.
- Rejected, with the reason, so nobody proposes them again: **Apache NetBeans**
  is larger (~1.5M lines) but its module system is not Maven, so it exercises
  the wrong build path; **Elasticsearch** and **Kafka** reach the line count with
  Gradle and few modules, which is the wrong problem — they are good corpora for
  raw editor and index load and bad ones for the 500-bundle question.

Two corpora, then: Papyrus for the loop, Platform for the real number.

## What to measure, before changing anything

Each of these wants a number on the two corpora and on a small project for
contrast:

- **Time to a window** and, separately, **time to something usable** — they are
  not the same, and the second is what somebody feels.
- **Time until Java answers** — completion, go-to-definition — which is jdtls
  indexing and is likely to dominate everything else.
- **Memory**, ours and jdtls's, at rest and after an hour.
- **Keystroke latency** in a file in a large bundle, which is the thing that
  makes an editor feel cheap when it is wrong.
- **`git status` time** on a repository that size.
- **Filesystem events per build**, and what the tree does with them.
- **Search**, first result and all results.

The suite measures processor time properly as of 0416, so the machinery is
there; what is missing is a harness that opens a real project and reports these.

## What will hurt first, from reading the code — to be confirmed, not assumed

- **jdtls at that scale is most of the answer.** Its own indexing of 500 bundles
  is minutes and gigabytes, and much of "fast" will be about what it is asked and
  when — not about our code. Related: 0427, servers that are not reaped and run
  the wrong toolchain.
- **`FileNode.read` sorts every directory** and `handleFilesystemChange`
  re-reads every expanded directory on each event. A build in 500 bundles
  touches thousands of paths.
- **`git status` on every filesystem change.** Already coalesced — one at a time
  with at most one queued — which was enough for this repository and will not be
  at that size.
- **Whatever the editor does per keystroke**, which is measured today only on one
  large file rather than in a large project.

## Worth deciding

- Whether the corpus is vendored, cloned by a script, or expected beside the
  checkout. It is gigabytes; the examples repository is the precedent for "beside
  the checkout", and the screenshot harness already assumes that shape.
- Whether these measurements run in CI or by hand. They take minutes and need a
  large checkout, so probably by hand with the numbers written down here — the
  point is a baseline that can be compared against, not a gate.

---

Its number is where it sits in the queue, not what it is worth doing next.
