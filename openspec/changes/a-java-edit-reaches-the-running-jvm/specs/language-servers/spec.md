## MODIFIED Requirements

### Requirement: Debugging Java does not depend on which server edits it

Debugging Java SHALL NOT depend on which server edits it.

The Java debug adapter is an Eclipse bundle loaded *inside* jdtls rather than a
program beside it — so it needs a jdtls, and it needs one that has imported the
project, because a launch is a class and a classpath and the import is what
computes the classpath. What it does **not** need is for jdtls to be the server
answering about files. A project that chose the fast syntactic server for
editing, because its five hundred bundles take minutes and gigabytes to import,
gets a jdtls started for the debugger alone.

**Started when somebody presses Debug, and not before.** Importing at every
project open would be instant debugging paid for by every session that never
debugs, which is most of them and is exactly the cost the fast server was chosen
to avoid. So the first Debug of a session waits, and **says what it is waiting
for** while it does: how long it has been, and what the server itself last said
about how far it has got. A wait that says nothing is indistinguishable from a
debugger that has hung.

**It answers nothing about any file.** The chosen server answers about files and
this one answers three questions about the project — where the adapter is
listening, what the classpath is, and compiling what it has imported. It is not
in the table that requests and open documents are routed through, it is never
told a document is open, and the compilation problems jdtls reports for
everything it imports reach nothing. Two servers over one file with two sets of
diagnostics and no rule for which wins is still refused; this is not that.

**Compiling is the third question and is asked while a session runs**, not only
before one starts. A change on disk is not a class file until this server has
been asked, which is why a launch compiles first; a swap into a running JVM needs
the same thing for the same reason, so the same request serves both. It remains a
question about the project rather than about a file: what is asked for is a build,
and what comes back is class files on disk.

**A project whose Java server is jdtls already debugs through the server it has.**
Nothing starts a second jdtls beside a jdtls: the one that is running has the
import, and a second would spend the minutes again for the same answer and hold a
second copy of it. And should the project's choice move to a server that hosts
the adapter, the one started for the debugger is stopped, since what it holds is
then a gigabyte of nothing.

**A project worked on inside its own devcontainer still has no Java debugger**,
and now says so. The bundle is a path on this machine and the JVM would be this
machine's, so what got debugged would be a different toolchain from the one the
project builds with — which is the whole reason a devcontainer's servers live in
there.

**Nothing is launched on a classpath that is not this project's.** Three ways a
classpath is not one, and all three used to end in a JVM dying of something that
read as the project's fault:

- The server answers about **its own fallback workspace** rather than about this
  project, which is what it does until the import has finished. A well-formed
  answer for the wrong thing, and taken at face value it compiles against whatever
  the newest toolchain on the machine is and then fails on the class file version.
  So an answer counts only when it is *about* the project.
- The classpath names directories the server **has not compiled into yet**, since
  it fills them after the import. So the project is compiled before the JVM
  starts.
- The server answers, at once and for ever, that there **is no classpath** — which
  is what an OSGi bundle gets, its dependencies being a target platform rather
  than anything in its build file. That is an answer and not a wait, and it is
  said as one: nothing is started, and nobody is left watching a spinner for
  something that has already happened. **A swap into such a project SHALL NOT ask
  this server to compile it**, for the same reason: the answer is already known.

#### Scenario: a classpath the server has not worked out yet

- **Given** a Java project whose server has not finished importing it
- **When** a class in it is debugged
- **Then** no JVM is started on the classpath the server answers with meanwhile
- **And** what is being waited for is said, until the answer is about this project

#### Scenario: a project whose classpath the server cannot report

- **Given** an OSGi bundle, whose dependencies are in its manifest rather than in
  its build file
- **When** a class in it is debugged
- **Then** it says the server reports no classpath, and that this is its answer
  rather than a wait
- **And** no JVM is started

#### Scenario: debugging a project whose editing server is the syntactic one

- **Given** a Java project whose `.abydos/tools.json` chooses the server that
  hosts no debug adapter
- **When** a class in it is debugged
- **Then** jdtls is started for the debugger alone and the session runs
- **And** while it is waited for, what is being waited for is said, with how long
  it has been

#### Scenario: what the debugger's server is asked

- **Given** a debugging session running through a jdtls started for the debugger
- **When** a file in the project is opened, edited and asked about
- **Then** that server is told nothing about it and is asked nothing about it
- **And** nothing it says about any file appears anywhere

#### Scenario: compiling for a swap rather than for a launch

- **Given** a debugging session running through a jdtls started for the debugger
- **When** a source file is saved during that session
- **Then** that server is asked to compile, and answers with class files on disk
- **And** it is still asked nothing about any file

#### Scenario: the editing server already hosts the adapter

- **Given** a Java project whose server is jdtls, running and importing finished
- **When** a class in it is debugged
- **Then** the session goes through that server and no second one is started

#### Scenario: a project worked on in its devcontainer

- **Given** a Java project whose servers run inside its own devcontainer
- **When** a class in it is debugged
- **Then** it says the debugger is a bundle loaded into a jdtls on this machine,
  and that working on this machine is what it would take
