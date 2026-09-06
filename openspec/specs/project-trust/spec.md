# project-trust Specification

## Purpose
TBD - created by archiving change a-project-is-trusted-before-it-runs. Update Purpose after archive.
## Requirements
### Requirement: A project is untrusted until somebody trusts it

A project SHALL be untrusted when it is opened and this application has not
been told otherwise, whatever it contains and however it was opened. Reading it
SHALL be unaffected — the tree, the editor, syntax, folding, search, the git
panes, history, diffs, blame and the previews this app renders itself — because
a mode that cannot read is a mode nobody stays in long enough to be protected
by.

#### Scenario: a repository just cloned to look at

- **GIVEN** a project this application has never been told to trust
- **WHEN** it is opened
- **THEN** its files, its history and its diffs can be read

#### Scenario: opening does not run anything

- **GIVEN** an untrusted project carrying a `Makefile`, a `launch.json` and a devcontainer definition
- **WHEN** it is opened
- **THEN** nothing from it is started

### Requirement: An untrusted project executes nothing of its own

While a project is untrusted the application SHALL NOT start anything the
project supplies or names: no run, debug, build or test configuration; no Make
goal, gradle or maven wrapper; no devcontainer and no image it names; no
language server, formatter or linter, whether found in the project's tree or
chosen by its files; and no agent command it carries.

**A terminal SHALL still open.** The shell is the person's own, with their own
configuration, and what they type into it is their choosing — running `make`
there is what they would do in any terminal, and this application's job is not
to police typing but to start nothing itself. Refusing one would cost the way
somebody moves between projects in a terminal-first editor and buy almost
nothing. What the shell must not do on its own is run the *project's* files, so
an untrusted project's terminal SHALL be given `DIRENV_DISABLE`, which is belt
to direnv's own brace — it refuses an `.envrc` it has not been allowed — and
best-effort by nature.

Each refusal SHALL say the same thing in the same words — that the project is
not trusted — and SHALL offer the one gesture that changes it, rather than
failing as though something were broken.

**A refused run SHALL leave the window saying so**, not saying what a run in
progress says. A press that reaches a refusal deeper than itself leaves
whatever it had already put in the titlebar — a stop button, a busy line, the
colour of a running program — and a window that looks like it is running
something is a window nobody presses anything else in. The run control SHALL
end as a failure ends.

#### Scenario: pressing run

- **GIVEN** an untrusted project with a run configuration discovered
- **WHEN** run is pressed
- **THEN** nothing is launched, and what is said names the trust and offers to grant it
- **AND** the run control reads as a failure rather than as a run in progress

#### Scenario: the language server

- **GIVEN** an untrusted project whose tree carries a language server binary
- **WHEN** a file that would use it is opened
- **THEN** no server is started, and the editor works without one

#### Scenario: the terminal opens, and runs none of the project's files

- **GIVEN** an untrusted project with an `.envrc`
- **WHEN** the terminal is opened
- **THEN** a shell starts in the project's directory, with `DIRENV_DISABLE` set, and nothing of the project's has run

#### Scenario: a devcontainer

- **GIVEN** an untrusted project with a devcontainer definition
- **WHEN** it would otherwise be offered or started
- **THEN** it is not started

### Requirement: No environment variable the project supplies reaches a process

While a project is untrusted, no environment variable it supplies SHALL be
applied to any process this application starts, for the project or for itself
— not a `launch.json` `env` block, not a devcontainer's `containerEnv`, not an
`.envrc`, not a run configuration's own environment. A variable is a command in
every case that matters: `SOPS_AGE_KEY_CMD` is run by sops, `GIT_SSH_COMMAND`
and `GIT_EXTERNAL_DIFF` by git, and the dynamic loader's variables choose what
is loaded into a process that was never asked.

The application's own environment SHALL be unaffected, being this
application's and not the project's. Variables SHALL be dropped rather than
filtered against a list of dangerous names: the dangerous ones do not look
dangerous, and a list of them is a list somebody has to keep correct forever.

#### Scenario: a decrypt in an untrusted project

- **GIVEN** an untrusted project whose files set `SOPS_AGE_KEY_CMD`
- **WHEN** a SOPS file is decrypted
- **THEN** that variable is not in the environment sops is run with

#### Scenario: a launch configuration's environment

- **GIVEN** an untrusted project whose `launch.json` sets `DYLD_INSERT_LIBRARIES`
- **THEN** nothing is launched at all, and the variable reaches nothing

#### Scenario: the application's own environment

- **GIVEN** an untrusted project
- **WHEN** the application runs git on it
- **THEN** git runs with the environment this application gives it, unchanged

### Requirement: A git write that would run the project's hooks says so

A commit made in an untrusted project SHALL NOT run the project's hooks, and
what is said where the commit is made SHALL say that the hooks were declined —
`.git/hooks` being code the project carries and a clone brings with it.
Committing SHALL NOT be refused outright: reading a repository and committing to
it is work somebody may legitimately be doing, and a mode that cannot commit is
a mode they leave.

#### Scenario: committing in an untrusted project

- **GIVEN** an untrusted project with a `pre-commit` hook
- **WHEN** a commit is made
- **THEN** the commit is made, the hook does not run, and what is said names that

#### Scenario: once it is trusted

- **GIVEN** the same project trusted
- **WHEN** a commit is made
- **THEN** the hook runs as it always did

### Requirement: Trust is remembered per folder, outside the project

Trust SHALL be remembered in this application's own support directory, beside
the recent projects it already keeps there, as the folder's resolved path, when
it was trusted and by which gesture. It SHALL NOT be remembered inside the
project under any name: a project that can grant itself trust is the hole this
requirement exists to close.

Trusting a **parent folder** SHALL be offered and SHALL cover everything under
it, matched on the resolved path at a component boundary, so that a folder of
checkouts is answered once rather than once per checkout. A driven run SHALL
keep the list in memory and SHALL NOT write it, as the recent projects list
already does not.

#### Scenario: trusting a project

- **GIVEN** an untrusted project
- **WHEN** it is trusted
- **THEN** it opens trusted next time, without asking again

#### Scenario: trusting a folder of checkouts

- **GIVEN** `~/dev` trusted as a parent
- **WHEN** `~/dev/anything` is opened
- **THEN** it is trusted, and nothing asks

#### Scenario: a name that only looks like it is under a trusted parent

- **GIVEN** `~/dev` trusted as a parent
- **WHEN** `~/development/thing` is opened
- **THEN** it is untrusted

#### Scenario: the project cannot grant itself

- **GIVEN** an untrusted project carrying any file claiming trust
- **WHEN** it is opened
- **THEN** it is untrusted

#### Scenario: a driven run leaves no trace

- **GIVEN** a driven run that trusts a temporary project
- **THEN** the list on disk is unchanged when it ends

### Requirement: The window says what is held back, and one gesture changes it

An untrusted project's window SHALL say so where it can be read without being
in the way — a strip rather than a modal, naming what is held back and carrying
the gesture that grants trust. Granting SHALL name the folder, offer the parent
folder as the wider choice, and say what trusting turns on.

**What is held back SHALL be readable for as long as somebody is reading it**,
and SHALL say what still works beside what does not: it is a list somebody
consults while deciding, and half of it — the reading that is unaffected — is
the half that makes "look first, decide later" an option. A notice that goes on
a timer is not that.

**Trusting SHALL be a choice of scope made from a menu**, on the strip's own
button and in the application's menus alike: this project, the folder it sits
in, or where a clone says it came from. The menu SHALL appear at the control
that opened it. A scope that reaches beyond the project in front of somebody —
a folder of checkouts, a remote anything can claim to come from — SHALL say
what it covers before it is granted; trusting the project being looked at SHALL
be the press itself.

**Trust SHALL be withdrawable from the same menu**, naming the entry that
grants it — which may be a parent folder or a remote, and so may cover more
than this project; that SHALL be said before it is taken back.

**The strip SHALL be dismissable without trusting anything.** A strip that can
only be got rid of by trusting the project is a strip that gets projects
trusted. Dismissing it SHALL change nothing about the project — it stays
untrusted and everything still refuses — and SHALL last only until that project
is opened again. The gesture that grants trust SHALL remain reachable with the
strip gone, from the application's own menus.

Trust SHALL be listed and withdrawable in the settings, and withdrawing it SHALL
return the project to what an unknown project gets.

#### Scenario: the strip

- **GIVEN** an untrusted project open
- **THEN** the window says it is untrusted, what that holds back, and offers to trust it

#### Scenario: the sheet says what it turns on

- **WHEN** the trust gesture is used
- **THEN** what is asked names the folder, offers the parent folder, and says what trusting allows

#### Scenario: what is held back stays on screen

- **WHEN** the strip's *What is held back* is chosen
- **THEN** what is listed stays until it is dismissed, and says what still works as well as what does not

#### Scenario: putting the strip away

- **GIVEN** an untrusted project showing the strip
- **WHEN** the strip is dismissed
- **THEN** it goes, the project is still untrusted, and running anything still refuses

#### Scenario: trusting once the strip is gone

- **GIVEN** the strip dismissed
- **WHEN** the application's menu is used to trust the project
- **THEN** the same sheet opens

#### Scenario: taking it back

- **GIVEN** a trusted project
- **WHEN** its trust is withdrawn in the settings
- **THEN** the project is untrusted again, and nothing of its own runs

#### Scenario: the scopes are a menu at the button

- **WHEN** the strip's trust button is pressed
- **THEN** a menu of scopes opens at that button

#### Scenario: untrusting from the same menu

- **GIVEN** a project trusted by a parent folder
- **WHEN** the trust menu is opened
- **THEN** it says which entry trusts the project and offers to take that entry back, saying what else it covers

### Requirement: Trust can be granted to where a clone came from

Trust SHALL also be grantable by the remote a project says it was cloned from
— a host, for a server whose every repository is a colleague's, or an owner on
a host, since one organisation is a place and `github.com` is the world. A
project whose `origin` names a trusted host, or a trusted owner on that host,
SHALL be trusted without a folder entry of its own.

**A public forge SHALL NOT be offered as a whole host.** `github.com`,
`gitlab.com` and the rest are every repository anybody has ever pushed;
offering one beside "this organisation", as though they were two sizes of the
same thing, is how somebody picks the wrong one. On those the owner is the only
remote scope offered. A host the application does not know SHALL be treated as
somebody's own server, since one scope too narrow is the safe way to be wrong.

Where this is offered, and where trusted remotes are listed, it SHALL say what
it is worth: **a repository's remote is what its own `.git/config` claims**, so
trusting a remote trusts every folder that says it came from there. It is
weaker than a folder deliberately, and somebody granting it is owed that
sentence before they do.

The remote SHALL be read once when the project is opened rather than at each
refusal: a subprocess between a keypress and a refusal is a refusal that
arrives late.

#### Scenario: an enterprise server

- **GIVEN** a project whose `origin` is `git@git.company.com:platform/thing.git`
- **WHEN** `git.company.com` is trusted
- **THEN** that project is trusted, and so is the next clone from that server

#### Scenario: one organisation, not the whole of github.com

- **GIVEN** `github.com/my-org` trusted
- **WHEN** a project cloned from `github.com/somebody-else` is opened
- **THEN** it is untrusted

#### Scenario: the world is not offered as a scope

- **GIVEN** a project cloned from `github.com/philipparndt`
- **WHEN** the trust scopes are offered
- **THEN** `github.com/philipparndt` is among them and `github.com` is not

#### Scenario: an enterprise host is

- **GIVEN** a project cloned from `github.company.com/my-org`
- **WHEN** the trust scopes are offered
- **THEN** both `github.company.com/my-org` and `github.company.com` are among them

#### Scenario: what it is worth is said

- **WHEN** trusting a remote is offered
- **THEN** what is said is that a repository's remote is its own claim, and that this trusts anything claiming to come from there

#### Scenario: a project with no remote

- **GIVEN** a trusted host and a project with no `origin` at all
- **WHEN** it is opened
- **THEN** it is untrusted

