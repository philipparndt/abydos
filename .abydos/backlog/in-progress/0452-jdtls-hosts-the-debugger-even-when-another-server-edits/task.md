# 452. jdtls hosts the debugger even when another server edits

0449 lets a project choose its Java server and 0450 measured why somebody would:
on a 143-bundle project jdtls was still silent at 601 seconds where kmp-lsp
answered in 2.6. But choosing kmp-lsp today costs the debugger entirely, because
**java-debug is an Eclipse bundle loaded inside jdtls** — `DebugAdapters.java`
says so, and `LanguageServers.swift` passes it as the `bundles` option under
`guard definition.setup == .java`. No jdtls, no adapter, no debugging.

That is a bad trade to have to make. The fast server is wanted for editing five
hundred bundles; the debugger is wanted a few times a day. Nothing about those
two facts requires choosing between them.

## This is not what 0449 ruled out

0449 rejected two servers for one language, and the reason was specific: two sets
of diagnostics over one file with no rule for which wins. **These two have
disjoint jobs.** kmp-lsp answers about files; jdtls, in this arrangement, answers
about nothing at all and exists to host an adapter. Nobody has to decide which
completion is right, because only one of them is asked.

Whoever picks this up should not cite 0449 as a reason not to — but should make
the disjointness real in the code rather than in a comment, because a second
Java server that starts answering `textDocument/*` is exactly the mess 0449
refused.

## The cost, which is the whole design question

jdtls's expense is not its startup, it is **importing the project** — resolving
the classpath from the poms, which on a Tycho reactor is minutes and gigabytes.
And the adapter needs that import: it launches a class with a classpath, and the
classpath is what the import computes.

So "start jdtls only for debugging" means paying the import when somebody presses
Debug. Three ways, and they are not equally good:

- **On first debug.** Honest and slow: the first Debug of a session waits for an
  import it cannot skip. It must say what it is waiting for — a spinner that
  looks like the debugger hanging is worse than the wait.
- **When the project opens, in the background.** Debug is instant and the machine
  pays the whole import for a session that may never debug — which is most of
  them, and is the cost 0450 was trying to escape.
- **Neither: get the classpath elsewhere.** `mvn dependency:build-classpath` and
  `mvn help:evaluate` can answer without jdtls at all, and a launch needs a
  classpath and a main class rather than a language server. That is a different
  and possibly much better design, and it is the one worth an hour of thought
  before writing any of the above. It would also mean Gradle needs its own
  answer, and Tycho likely needs jdtls regardless, since a p2-resolved classpath
  is not something Maven prints.

Measure before choosing. 0450 left `--report-answer` and `Scripts/scale.sh`
behind and the corpus is cloned; how long an import takes before the *adapter*
can launch something is a number nobody has taken, and it may be far shorter than
the ten minutes completion needed.

## Worth knowing

- `JavaTooling.debugPlugin()` finds the bundle, overridable with
  `ABYDOS_JAVA_DEBUG_PLUGIN`, and `!inContainer` guards it — a devcontainer's
  jdtls is given no bundle at all, so debugging in a container is already absent
  and this item should not pretend otherwise.
- `DebugAdapters.for(...)` picks Java by finding a build file, not by asking
  which server is running, so it will already offer to debug a project whose
  editing server is kmp-lsp — and today that offer cannot be honoured. Whatever
  else changes, that lie should stop.

## Estimate

2026-08-11 15:37 — about three hours left, first measurement in

## Steps

- [x] A way to ask the question at all: `--report-answer` polls the three
      questions an editor asks, and neither of the debugger's two could be asked
      — added, beside them, on their own clock
- [ ] Measure how long jdtls needs before the *adapter* can launch, as against
      before completion answers — the two may be very different
- [ ] Decide where the classpath comes from, and write down why: jdtls's import,
      or Maven directly
- [ ] A second Java server that hosts the adapter and answers nothing about
      files, enforced rather than described
- [ ] Debug offered only when it can actually be honoured
- [ ] Say, where somebody chooses a server, what it costs them — 0449 already
      shows the choice; this is the sentence beside it
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
