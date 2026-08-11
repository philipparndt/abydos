## ADDED Requirement: The footer says which server is answering, and from where

Beside the caret's position and the language, the editor's footer names the
language server answering for the file in front of somebody — and says where
that server came from, which is the half that was missing. An installed copy, an
image and the project's own devcontainer are three different answers, and the
first is the one people assume: a Rust project pointed at an image that started,
initialised and answered was indistinguishable from nothing having happened, and
the only places that knew were the container runtime, `lsp.log`, and a window
somebody has to go and open.

The copy installed here is named and no more. A server from an image is named
with the container mark the titlebar's pill already wears and then the image, in
full, because which image is exactly what somebody wants to know and is written
nowhere else on screen. A server inside the project's devcontainer wears the mark
and stops there: the container is a fact about the window, the pill already names
it, and repeating it under every file would be the same word over and over.

A server on its way says so in one word — fetching, building, starting — and the
three are three because they are three different waits: the network, this
machine's compiler for a couple of minutes, and the project's container coming
up. The words agree with the strip above the file because both are written in one
place.

**And it is quiet when there is nothing to name.** A language with no server
running and none coming gets no chip at all, which is most files in most
projects; a footer that talks about every one of them is a footer people stop
reading, and what there is to say about a *missing* server is the strip above the
file, which has room for the sentence and for the way to fix it.

Clicking it opens the list of what is running. That is where the questions the
chip raises are answered — whether it is really running, what it costs, which
executable was resolved, and how to stop it — and it is not the settings page,
which is where the answer is changed but which knows no project.

**What it says is pushed to it, never asked for while drawing.** The footer is
redrawn every time the caret moves and draws the position in the same view, so it
holds the words and works nothing out; the words are worked out when a server
starts, stops, is refused or is reconsidered, which the app already announces.

### Scenario: a server answering from an image

- **Given** a Rust project whose `.abydos/tools.json` names an image for
  `rust-analyzer`
- **When** a `.rs` file in it is opened and the server is answering
- **Then** the footer names `rust-analyzer`, the container mark, and the image
- **And** the strip above the file says nothing, because nothing is wrong

### Scenario: a server in the project's devcontainer

- **Given** a project worked in its devcontainer, with a server running inside
- **When** a file it answers for is open
- **Then** the footer names the server and the container mark, and does not
  repeat the container's name, which the titlebar's pill is already showing

### Scenario: a file whose language has no server

- **Given** a file of a language nothing is running for and nothing is coming
  for
- **Then** the footer says where the caret is and what the language is, and
  nothing about a server

### Scenario: a server on its way

- **Given** a server whose image is being fetched
- **When** a file it will answer for is open
- **Then** the footer says the server is fetching
- **And** it says the same thing the strip above the file says

### Scenario: the caret moves

- **Given** a file with a server answering for it
- **When** the caret is moved
- **Then** nothing is looked up to draw the footer: what it says was settled when
  the server's state last changed

## MODIFIED Requirement: What is running can be seen and stopped

View ▸ Running Servers and Containers lists the language servers and containers
this app has started and has not ended, and every row has a Stop. It is what
makes keeping a server until the app quits an affordable decision rather than a
leak: a session that has collected nine of them is visible without anybody
running `ps`.

It is also where the footer's chip leads. Somebody who has just read which server
is answering for their file has four questions next — is it really running, what
is it costing, which executable did the system resolve, and how do I stop it —
and this window is the one place all four are answered.

A row's memory is the process **and everything it started**, with the count of
processes beside it, because the server is not where the weight is — measured on
one repository, `sourcekit-lsp` alone reads 32.7 MB and the same server with the
three processes underneath it reads 410.8 MB. A row also says which executable
the operating system resolved, which is how the toolchain requirement above
stays true where somebody can see it.

Beside the project a row names, a server somebody *chose* says which language it
was chosen for and where the choice was written. It is the one place a project's
choice can be seen rather than inferred — the settings page knows no project —
and the person reading it is exactly the one wondering why the server running is
the one they are paying for.

A server running inside the project's devcontainer says where it lives and
gives no number, since its client out here is a few megabytes and the container
below it is a row of its own. Stopping a server that has a container of its own
stops the container; stopping a server inside the project's devcontainer does
not, because that container is the project's and holds somebody's terminal.

The list is read when somebody looks at it — opening it, bringing it to the
front, pressing Refresh, stopping something — and never on a timer, because
asking a container runtime for memory costs about a second of its attention.

### Scenario: stopping a server, and needing it again

- **Given** a running server in the list
- **When** its Stop is pressed
- **Then** the row goes, and the process is no longer running
- **And** when a file needs that server again it starts, and the list has a row
  for it

### Scenario: a server in the project's devcontainer

- **Given** a project worked in its devcontainer, with a server running inside
- **Then** the server's row says which container it is in and gives no memory
- **And** the container has a row of its own, with the memory on it

### Scenario: a server the project chose

- **Given** a project whose `.abydos/tools.json` names the server for a language
- **When** that server is running and the list is read
- **Then** its row says the language it was chosen for and that the choice came
  from `.abydos/tools.json`

### Scenario: arriving from the footer

- **Given** a file whose footer names the server answering for it
- **When** the footer's chip is clicked
- **Then** this list opens, with a row for that server
