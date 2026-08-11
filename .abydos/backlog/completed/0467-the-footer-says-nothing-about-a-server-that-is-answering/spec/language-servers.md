## MODIFIED Requirement: The footer says which server is answering, and from where

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

**A name that fits is drawn however short it is.** The chip is what gives way
when the editor is narrow, and it gives way in two stages: it is cut at the tail
first, and dropped entirely when what is left would be too little to read — a
chip saying `ru…` says nothing anybody can use, and what it crowds out is where
the caret is. That floor is a claim about the *room*, never about the name: a
server called `gopls` is a third the width of one called `rust-analyzer` and
wants none of the room the rule is about, and a bar wide enough for a long name
is wide enough for a short one.

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

### Scenario: a short name in a wide editor

- **Given** a Go project whose `go.mod` is in a subdirectory, with `gopls`
  installed on this machine and answering
- **When** a `.go` file in it is open in an editor the width of a window
- **Then** the footer reads `gopls` and nothing else, beside the position and
  the language
- **And** it is not dropped for being short: what may drop it is the room it has,
  not how much of that room it wants

### Scenario: a chip with nowhere to go

- **Given** a server whose name and image together are wider than the bar's
  remaining space
- **When** what is left would be too few characters to read
- **Then** no chip is drawn at all, and the language and the caret's position
  keep their place

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
