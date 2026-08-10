# 449. A project chooses which language server it wants

A language has exactly one server here:

    public static func definition(forLanguage languageId: String) -> LanguageServerDefinition? {
        known.first { $0.languageIds.contains(languageId) }
    }

Java means jdtls, and there is no way to say otherwise. That was fine while
there was one plausible server per language, and it is not any more — Java in
particular now has a real alternative with a different trade, and which trade is
right depends on the project rather than on the machine.

**The case that prompted this.** A Maven/Tycho product of ~500 pom-first
bundles. jdtls understands it — the pom is where the classpath comes from and
jdtls reads it — at the price of a JVM, an import of the whole reactor, and 1.9
GB. [kmp-lsp](https://github.com/Hessesian/kmp-lsp) is the other end: Rust,
tree-sitter, no JVM, instant start, and **syntactic only — no type checking**.
Its library sources come from `~/.gradle/caches` and IntelliJ's
`workspace.json`; nothing in it mentions Maven, let alone a Tycho target
platform. So on pom-first bundles it would likely navigate your own source and
not into dependencies.

That is exactly why this is a *choice* and not a replacement. Neither is wrong;
they answer different questions, and only the person with the project knows
which they are asking.

## Where the choice belongs

`.abydos/tools.json` already exists, is the project's own file, and already
decides where a tool comes from — an image name per tool. This is one step up
from that: which *server* a language uses at all.

    { "java": "kmp-lsp" }

The obvious risk is that a project file and a machine preference disagree, and
0424 already settled that shape for diagram themes: **the file wins, the app's
setting is the default.** Follow it rather than inventing a second rule.

## What has to change

- `LanguageServerDefinition` needs a name of its own, distinct from its
  `command` — two Java servers cannot both be "the Java one".
- `known` becomes several definitions per language rather than one, and
  `definition(forLanguage:)` has to take the project into account. Every caller
  of it is a place that assumed one answer.
- A chosen server that is not installed and has no image is a sentence, not a
  silence — and it must not quietly fall back to the other one, or somebody
  will spend an afternoon wondering why their fast server is using 1.9 GB.
- The tool settings page has a child per tool already; a language with two
  candidates wants to show which is in use and why.

## Ruled out

**Choosing automatically from the build files.** A `pom.xml` could pick jdtls
and a `build.gradle` kmp-lsp, and it would be wrong for exactly the person this
item is for: their reason for wanting the fast one is that the slow one is
painful *on the project the pom describes*. Guessing takes the choice away at
the moment it matters most.

**Both at once.** Two servers for one language means two sets of diagnostics
over one file and no rule for which wins. Rejected without measurement.

## Steps

- [ ] A definition carries a name, and a language may have several
- [ ] `.abydos/tools.json` names a language's server; the file wins, the setting
      is the default, as 0424 already decided for themes
- [ ] A named server that cannot be started says so and does not fall back
- [ ] The settings page shows which server a language is using and where the
      choice came from
- [ ] A second Java server actually driven end to end against a Maven project
      and a Gradle one, so the caveat above is measured rather than repeated
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
