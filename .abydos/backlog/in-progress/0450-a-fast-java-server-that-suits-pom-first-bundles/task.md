# 450. A fast Java server that suits pom-first bundles

0449 gives a project the choice of *which* Java server. This is the third
candidate that choice does not have yet: something with kmp-lsp's cost and a
Maven project's idea of where source lives.

**Do not start this before 0449, and probably not before the measurement below.**
It is the largest of the three and the only one that reaches outside this
repository.

## The three, and what separates them

| | jdtls | kmp-lsp | this |
|---|---|---|---|
| runtime | JVM | none | none |
| start | reactor import | instant | instant |
| analysis | full, type-aware | syntactic only | syntactic only |
| library sources | from the pom | `~/.gradle/caches` | `~/.m2/repository` |
| ~500 pom-first bundles | understands them, 1.9 GB | own source only | the point |

## Maven is small; Tycho is not, and they are being confused

**The `~/.m2` half is a locator swap.** kmp-lsp finds `*-sources.jar` under
`~/.gradle/caches`; Maven's equivalent is a defined path,
`~/.m2/repository/<group>/<artifact>/<version>/<artifact>-<version>-sources.jar`.
That is a contained change, not a redesign.

**The Tycho half is a different program.** A Tycho bundle's classpath does not
come from the pom's `<dependencies>`. It comes from the OSGi target platform and
`MANIFEST.MF` — `Require-Bundle`, `Import-Package` — resolved against p2
repositories. Computing that is reimplementing a chunk of what PDE does, and it
is the reason jdtls is heavy rather than an oversight in it.

**And here is why this may be far smaller than it looks:** kmp-lsp is syntactic.
It indexes source with tree-sitter. It needs no classpath at all to give symbols,
outline, references and go-to-definition **within the five hundred bundles you
wrote** — which is most of what somebody wants it for. The classpath decides only
whether you can step *into* a dependency. So the honest first version may need
only the `~/.m2` locator, with target-platform resolution as a stretch that never
becomes necessary.

## A fork to work in, contributed back when it is proved

The intent, stated by the person who asked for it: fork it, implement the Maven
support, and offer it upstream once convinced it actually works. That is the
ordinary way to contribute and it is the right shape here — the change touches
somebody else's project, and a pull request that arrives with the work already
driven against a real 500-bundle reactor is worth far more than an issue asking
whether they would accept one.

kmp-lsp documents its own limitations plainly and has ~888 commits with real
releases, which is what a maintained project looks like. A `~/.m2` source
locator is contained and obviously correct, so it is a good candidate to be
taken.

**The thing to watch is not the fork, it is the fork outliving its purpose.** A
working copy becomes a permanent one by accident: the pull request stalls, the
upstream moves, and a year later somebody is maintaining a Rust language server
they did not mean to own. So this entry should record, when the work starts,
what happens if upstream does not take it — carry the patch and rebase it, or
stop and go back to jdtls. Deciding that up front costs nothing; discovering it
later costs the fork.

Worth telling them early, before the code: an issue saying "I have ~500
pom-first bundles and intend to add `~/.m2` source resolution, would you take
it" is one message, and the answer changes how much is built before it is
offered.

## Ruled out

**Writing a Java server from scratch.** The syntactic half is tree-sitter, which
this app already vendors for Java; the valuable half is the classpath, which is
the part that is hard. Anybody starting from nothing arrives where kmp-lsp
already is, later.

## Steps

- [x] 0449 first — without a way to choose, a third server has nowhere to be
      chosen. It landed the same day this was picked up.
- [x] A way to ask the question at all: every driver flag puts one question at a
      fixed delay, which can only say whether the delay was long enough
      — added, as `--report-answer <line:character>`
- [x] Take the number that decides whether any of this is needed: time until
      Java answers, with jdtls, on the corpus, now that 0446 has stopped the app
      drowning it out
- [x] Drive kmp-lsp unchanged against a pom-first project and say exactly what
      works and what does not — the caveat here is read from a README and has
      never been tested
- [ ] Ask upstream whether they would take `~/.m2` source resolution, before
      building much of it
      — **not done, and the order came out backwards.** The measurements said
      build it, and it is one contained commit that is easier to ask about with
      the diff and the numbers in hand than as a question. Asking is the user's
      to do: this is their fork and their pull request, and nothing here has
      been pushed.
- [x] Source-jar lookup under `~/.m2/repository`, in a fork, driven against a
      real pom-first reactor before it is offered
- [x] Both halves of the pipeline, not only the sources one — a real `~/.m2` is
      mostly compiled JARs, because Maven does not fetch sources unless asked
- [x] The second Java server exists in this app's own table, so a project can
      actually choose it. 0449 built the mechanism with nothing to choose
      between; this is the thing it was built for.
- [x] Record what happens if upstream does not take it: carry and rebase, or
      stop and stay with jdtls
- [x] Decide, and record, whether the target platform is ever needed
- [x] Write down here what was ruled out on the way
- [x] `spec/language-servers.md` says what the project now does

---

## What the measurements said

**Conditions, and they are not quiet ones.** A ten-core machine that was never
idle: the user's own Safari, an OrbStack VM, BambuStudio, a Kubernetes container
and an installed Abydos with a jdtls of its own put the floor at a load average
of 8 to 14, which is around one per core. Every reading below carries the load
it was taken at. Nothing else of this work ran during a measurement — the kmp-lsp
builds and the Rust test suite were taken outside every window here.

Two things are different from 0428's runs and both matter when comparing:

- **jdtls is the local one this time.** 0428's numbers were a container's,
  because the catalogue preferred `pharndt/abydos-jdtls:dev`. This app was built
  with a bundle id of its own and so has empty settings, no project named an
  image, and `/opt/homebrew/bin/jdtls` 1.60.0 on Java 21 is what ran. That is
  the cleaner measurement of the two: no virtual machine between the question
  and the answer.
- **Three orphaned jdtls containers were running before this started**, left by
  processes that had already died — 0428's finding 4, still true. They were
  stopped first, because a measurement taken beside three idle four-CPU guests
  describes the machine.

### Time until Java answers, with jdtls

Wall clock from the kernel's `p_starttime`, so the app's own launch is inside it.
`--report-answer` asks documentSymbol, completion and go-to-definition together
once a second until each answers; a round costs one ten-second request timeout
rather than three, so every figure is good to about a second.

| | Sirius, 106 bundles | eclipse.platform.ui, 143 bundles |
|---|---|---|
| outline of the open file | **25.8 s** | **29.3 s** (410 symbols) |
| completion | **25.8 s** | **still silent at 601 s** |
| go-to-definition | **25.8 s**, and correct — into another bundle | **still silent at 601 s** |
| jdtls resident at the end | 1.4 GB | **3.97 GB** |
| jdtls processor by then | 1 m 12 s at 90 s | **3 m 20 s** by 10 min |
| ours, processor / memory | 12.3 s / 121 MB at 90 s | 48.6 s / 118 MB at 10 min |
| load at the reading | 30.8 (3.1 per core) | 12.6 (1.3 per core) |

The two questions were asked at the same kind of position: a call whose target is
in another file — `SessionManagerImpl.init()` on Sirius, `fDocument.getLineInformation`
in `TextViewer.java` on the Platform.

**So the honest answer to "is jdtls acceptable once the app is not drowning it"
is: on the smaller project yes, and on the larger one no.** Twenty-six seconds
for a full type-aware answer over 8,307 files is a fair price and the item could
have closed there. Ten minutes of silence and four gigabytes on a project a
seventh larger again is not, and the product this is all for is larger than
either. 0446 was necessary and it is not sufficient.

What jdtls was doing in those ten minutes is visible in the corpus: it wrote
Eclipse metadata into 98 files across 79 directories and then went quiet at 3.97
GB. It never said it had failed, which is the worst shape for a wait to have.

### Time until Java answers, with kmp-lsp

Driven straight over stdio rather than through the editor, so what is measured is
the server. The whole workspace, not one file:

| | Sirius | eclipse.platform.ui |
|---|---|---|
| files indexed | 8,307 | 7,566 |
| symbols | 46,320 | 54,121 |
| **workspace ready** | **3.2 s** | **2.6 s** |
| go-to-definition | `SessionManagerImpl.java`, another bundle | `IDocument.java`, another bundle |
| hover | the Javadoc and the signature | the Javadoc and the signature |
| completion after the dot | 163 items | 500 items |
| resident (no sidecar) | — | **482 MB**, 6.9 s of processor |

On the exact file and position where jdtls was still silent at ten minutes,
kmp-lsp answered correctly in under three seconds for an eighth of the memory.

### What kmp-lsp unchanged does on a pom-first project

Driven on a two-module Maven reactor written for this, `bundle-app` depending on
`bundle-core` and on a real `~/.m2` artifact:

- **Its own reactor: yes.** Go-to-definition on a type name and on
  `new CoreService()` both land in the other module, with the class Javadoc on
  hover. Find-usages crosses modules. Workspace symbols find it.
- **Into a dependency: nothing at all.** Definition `null`, hover `null`, on the
  import line, on the type name and on a method call. The log says why:
  `65 compiled JARs, 18 sources JARs, all from Gradle cache`. The artifact is in
  `~/.m2` and nothing looked there.
- **A method on a *local variable* did not resolve** — `service.describe(…)`
  came back `null` while the same call on a field in the corpus resolved fine.
  That is a Java inference gap in the server, nothing to do with Maven, and it is
  not what this item is fixing.

Which is the entry's guess confirmed almost exactly: **it navigates the five
hundred bundles you wrote and stops at the dependency boundary.** The half that
matters most was already working before a line was written.

### What the `~/.m2` locator changed

`feat(jar): index the local Maven repository beside the Gradle cache`, on
`feat/maven-local-repository-jars` in the user's fork. On the same reactor:

| | before | after |
|---|---|---|
| compiled JARs indexed | 65 | **893** |
| sources JARs indexed | 18 | **19** |
| jar phase | 3.9 s | 9.9 s |
| go-to-definition into the dependency | `null` | `TelegramBot.java`, line 32 |
| hover | `null` | the constructor signature and its FQN |

The workspace index was ready at 0.5 s either way, so the jar phase is beside the
critical path rather than on it.

**The cost is memory, and it is real.** On `eclipse.platform.ui`, which needs
none of those jars, the server goes from 850 MB to 1,390 MB — the price of
manifesting 893 artifacts instead of 65. That is the pre-existing design of the
pipeline (the Gradle cache was already scanned wholesale and unconditionally),
made more expensive by there being more of it. It belongs in the pull request as
a stated cost, and the obvious follow-up — scan only what the project's build
files actually depend on — is a much larger change that the maintainers have
already argued against once, in the comment on `workspace_has_jvm_sources`.

## Ruled out, and other things found on the way

**The Tycho target platform. Not started, and now with a measurement behind the
decision rather than an argument.** kmp-lsp with no classpath at all already
answers go-to-definition, hover and completion across 7,566 files of an OSGi
product, because every one of those bundles is source it has indexed. The target
platform buys stepping into a p2-resolved dependency, and nothing measured here
suggests that is where the pain is. It stays refused.

**Opening the Platform *aggregate* as one project.** The first run of this was
taken against `~/dev/abydos-corpus/platform`, nine sibling clones with no pom at
the root, and jdtls rooted itself at `platform/eclipse.jdt.core` — the first
sibling that has one — while the file being asked about was in
`eclipse.platform.ui`. Every number from that run was about a project that did
not contain the file. It looked exactly like a slow server. 0428's finding 5 is
the same shape seen from the tree; this is it seen from the language server, and
it is why the numbers above are per repository.

**`--lsp-wait` as a way to time an answer.** It waits a fixed number of seconds
and then asks once, so it can report only whether the guess was long enough. Its
default is twelve seconds, which on either corpus reports silence from a server
that is working perfectly well. `--report-answer` polls, and the ten-second
request timeout inside `LSPClient` is what bounds a round.

**Believing the README about kmp-lsp's memory.** "< 200 MB" is true of the server
on its own. With `kmp-jar-indexer` — the JVM sidecar its own installer ships —
the pair on this corpus is 1.4 GB plus 1.3 GB of JVM. Worth knowing before
anybody chooses it *because* it is cheap: on the default `cargo install kmp-lsp`
there is no sidecar and it really is 482 MB.

**And the reason the first attempt at the `~/.m2` change appeared to do
nothing:** `spawn_jar_indexing` returns immediately when no sidecar is present,
so the sources-JAR half — which is pure tree-sitter and needs no sidecar at all —
never runs either. The whole pipeline is gated on a binary half of it does not
use. Not fixed here, because it is a separate claim about somebody else's code
and this branch should be one contained thing; it is worth an upstream issue.

**A jdtls belonging to the user's own Abydos was running throughout** and had to
be told apart from ours. `Scripts/scale.sh` only ever looks at its own app's
children, which 0428 built for exactly this, and it held.

## If upstream does not take it

Decided now, as the entry asked, rather than discovered in a year:

**Carry it, and only while it is one commit.** The change is a single commit
against `src/indexer/jar.rs` and its tests, in a file that has been stable, and
rebasing it costs minutes. That is affordable indefinitely. What is *not*
affordable is the shape this turns into if it is allowed to grow: the moment the
fork needs a second commit — the sidecar gate above, a per-project classpath,
anything about Tycho — the answer is to stop and stay with jdtls, because at that
point somebody owns a Rust language server they did not mean to own.

And the fallback is genuinely available, which is what makes carrying it a
low-risk choice rather than a commitment: a project that stops naming `kmp-lsp`
in `.abydos/tools.json` is answered by jdtls again, with no other change.

## The trade a project makes by choosing it

For the entry that 0449 asked 0450 to write, and it is not a small print item:

- **No type checking at all.** Syntax errors only. Nothing tells you a call has
  the wrong argument type; that comes from the build.
- **No debugging.** The Java debug adapter is an Eclipse bundle loaded *inside*
  jdtls, so a project whose Java server is this one has no adapter — 0449 made
  that a sentence rather than a dead button, and this is the item that makes
  somebody read it.
- **Find-usages is name-based** and says so: 718 hits for `init` on Sirius, no
  import filtering.
- **What you get for it:** the whole project navigable in under three seconds,
  for a fifth to an eighth of the memory, on a project where the other server
  answered nothing in ten minutes.
