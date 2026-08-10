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

## Upstream before forking

kmp-lsp documents its own limitations plainly and has ~888 commits with real
releases, which is what a maintained project looks like. A `~/.m2` source
locator is a contained, obviously-correct change of the kind upstreams take.

**A fork costs every future commit; a pull request costs one.** Fork as the
fallback if upstream declines or goes quiet, not as the opening move — and if it
is forked, say in this entry who keeps it current, because an unmaintained fork
of a fast-moving project is worse than the server nobody chose.

## Ruled out

**Writing a Java server from scratch.** The syntactic half is tree-sitter, which
this app already vendors for Java; the valuable half is the classpath, which is
the part that is hard. Anybody starting from nothing arrives where kmp-lsp
already is, later.

## Steps

- [ ] 0449 first — without a way to choose, a third server has nowhere to be
      chosen
- [ ] Take the number that decides whether any of this is needed: time until
      Java answers, with jdtls, on the corpus, now that 0446 has stopped the app
      drowning it out
- [ ] Drive kmp-lsp unchanged against a pom-first project and say exactly what
      works and what does not — the caveat here is read from a README and has
      never been tested
- [ ] Source-jar lookup under `~/.m2/repository`, offered upstream first
- [ ] Decide, and record, whether the target platform is ever needed
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
