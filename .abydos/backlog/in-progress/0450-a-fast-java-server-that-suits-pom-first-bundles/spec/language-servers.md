<!-- What this item changes about `language-servers`. Folded into
     .abydos/backlog/spec/language-servers.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A tool Xcode owns comes from Xcode, not from the PATH
       One search finds every tool this program runs
       A language server is kept until the app goes, and no longer
       One server per project per server, not per language
       What is running can be seen and stopped
       A project chooses which server answers for a language
       A chosen server that cannot be started says so
       The Java debugger belongs to the server that hosts it
-->

## ADDED Requirement: Java has two servers, and the one that reads the pom is the default

Java is the language with a second opinion, and it is where the choice above
stops being a mechanism and becomes something to make. `jdtls` reads the build
file, knows types, hosts the debugger, and costs a JVM and gigabytes. `kmp-lsp`
is Rust and tree-sitter: no JVM, no import of the build, no type checking at
all, and the whole project indexed in seconds.

Which is right depends on how large the project is, and the difference is not
small. Measured on Eclipse's `eclipse.platform.ui` — 143 bundles, 7,566 Java
files — jdtls answered an outline at 29 seconds and had said nothing about
completion or go-to-definition ten minutes later, holding 3.97 GB; kmp-lsp had
the whole project indexed at 2.6 seconds, answered go-to-definition into another
bundle, and held 482 MB. On the smaller Sirius, 106 bundles, jdtls answered
everything at 26 seconds, which is a perfectly fair price.

**jdtls is listed first and so remains the default**, because a second server
must change nothing for anybody who has not asked for it, and because the
project that fits in jdtls gets a better answer from it: types, and a debugger.
A project asks for the other one the way it asks for any of them, in
`.abydos/tools.json`.

Neither is installed on anybody's behalf, and the second is no exception:
`cargo install kmp-lsp`.

### Scenario: a project that says nothing about Java

- **Given** a Java project with no `.abydos/tools.json`
- **When** a `.java` file in it is opened
- **Then** `jdtls` is the server that starts

### Scenario: a project that asks for the fast one

- **Given** a Java project whose `.abydos/tools.json` says
  `{"languages": {"java": "kmp-lsp"}}`
- **When** a `.java` file in it is opened
- **Then** `kmp-lsp` is the server that starts, and `jdtls` is not

### Scenario: what the second server does not do

- **Given** a project whose chosen Java server is `kmp-lsp`
- **When** a debug session is started
- **Then** it says the debugger lives inside the other server, and names it
- **And** no diagnostic in the editor claims a type is wrong, because that
  server does not check types
