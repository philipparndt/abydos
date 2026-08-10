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

**`{ "java": "kmp-lsp" }` at the top level of `.abydos/tools.json`**, which is
what this entry drafted. The keys up there are tool names and these are language
ids, and `plantuml` is already both — a renderer that comes from an image and a
language a server answers for. One flat map would have a key whose meaning
depended on which reader got to it first, and `{"plantuml": "plantuml/plantuml"}`
would read as a language choosing a server nobody has. It went under a section of
its own:

    {
      "languages": { "java": "kmp-lsp" },
      "kmp-lsp":   "example/kmp-lsp:dev"
    }

which also puts on the face of the file the thing 0427 left the code with: which
server, and where that server comes from, are two questions.

**Reading the project's file inside `definition(forLanguage:)`.** It would have
saved threading a value through fourteen call sites. It is asked once per
document opened and once per query — the key a running server is filed under
depends on it — so a file read there is on the main actor at keystroke rate. The
choices are read once per project and held beside the images, which were already
held for the same reason.

**Letting an explicit choice waive the root markers.** A server chosen for a
project it shows no markers for is still not started, and that is unproven
rather than decided: it may well be right that naming a server is itself the
statement that this project is that language. Left alone because the sentence
that comes out of it — "you chose it and this project has none of the files it
looks for" — is not written yet, and a silent start at the project root would be
worse than the silence.

**A one-line summary of the trade on each candidate**, so that a menu offering
two Java servers says what the choice is between rather than two bare names. It
belongs with the second server rather than with the mechanism: 0450 is what
knows what kmp-lsp trades away.

## What it cost, and what surprised

**The Java debugger was the caller nobody would have looked for.** The debug
adapter is an Eclipse bundle loaded *inside* jdtls, so a project that chooses
another Java server has no debugging at all — a Debug button that does nothing
and explains nothing. It now says so, as the consequence of a choice, and the
condition is `setup == .java` rather than the name `jdtls`, since that is exactly
the servers the bundle is offered to.

**`languageIds.first` was the quiet one.** Two callers start one server per
definition and asked about its first language. clangd answers for `c`, `cpp` and
`objc`, so a project pointing `c` at another server would have started that other
server *as clangd*. `chosenLanguage(for:choosing:)` is the replacement, and it is
the kind of fault that would have taken a day to find from the symptom.

**Twenty places in Kit and the app assumed one answer**, and fifty-four call
sites in the tests. Most only needed the project's choice handed to them. The
four that were more than plumbing: the debugger above; `warmUp` and
`serverStatus`, for `languageIds.first`; and `serverKey`, which had to start
filing a server under its own name, so that changing the choice does not find
the entry the old server left and a refusal is remembered under the name that
was refused rather than under the server nobody chose.

**A settings page of one-option dropdowns is not as silly as it sounds.** Every
language is listed even where there is nothing to decide, because "Java: jdtls,
the only one Abydos has" is the answer to the question somebody opened the page
with. `objc` and `jsx` had no display name, so the page read "C, C++, objc"; both
went into `grammarlessNames`, which exists for exactly that.

**Driven for real**, on a scratch Maven project, against a build of its own
bundle id so as not to disturb the app the user has open:

- `{"languages": {"java": "kmp-lsp"}}` — the strip above the file reads *kmp-lsp
  was asked for and is not here, so this file has no language server*, and the
  log has the whole paragraph, naming jdtls and saying nothing has been started
  in its place. No Java server ran.
- `{"languages": {"java": "gopls"}}` — the same, with *gopls is a language server
  Abydos knows, but it answers for Go rather than for Java*.
- `{"languages": {"java": "jdtls"}}` — honoured, and Running Servers and
  Containers reads `jdtls | javaproj — Java, chosen in .abydos/tools.json | 26s |
  490,9 MB`. Which is the item's own argument on screen: half a gigabyte, for the
  server that reads the pom.

The settings page was checked by dumping its rows (`--dump-settings "Language
servers"`, which now finds child pages), not photographed: this machine's saved
layout opens with the terminal filling the window and the capture came back with
the terminal in it. The rows and their titles are what was verified.

**Two flaky tests, and neither is this change's.** Seven full runs: four green,
three with one failure each, in two places — `runsACommandAndCapturesOutput`
waiting on output from a pseudo-terminal, and `ContainerLSPLiveTests` comparing
the URI a containerised jdtls diagnosed first. Both were reproduced on the
commit this branch starts from, so they were there before. The first has the
hazard written in its own suite's comment: `forkpty` forks a multithreaded
process, and the whole suite running around it is exactly the load that makes it
matter.

## Steps

- [x] A definition carries a name, and a language may have several
- [x] `.abydos/tools.json` names a language's server; the file wins, the setting
      is the default, as 0424 already decided for themes
- [x] A named server that cannot be started says so and does not fall back
- [x] Every caller that assumed one answer per language found and handed the
      project's choice
- [x] The settings page shows which server a language is using, and the running
      list says where a project's choice came from
- [ ] A second Java server actually driven end to end against a Maven project
      and a Gradle one, so the caveat above is measured rather than repeated

      Not this item's: the second Java server is kmp-lsp and that is 0450. The
      mechanism is proved here against a table of two made up for the tests, and
      against the real one for the case that is real today — a project naming a
      server this app has not got.
- [x] Write down here what was ruled out on the way
- [x] `spec/language-servers.md` says what the project now does
