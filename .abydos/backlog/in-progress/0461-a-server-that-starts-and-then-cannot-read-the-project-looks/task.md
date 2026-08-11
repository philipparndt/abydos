# 461. A server that starts and then cannot read the project looks healthy

Reported from use, in the user's words: *"it is unclear that there is a problem
till I tried the outline."*

`rust-analyzer` started in its container, answered the handshake, and logged
`rust-analyzer initialized`. From the app's side that is a working server:
`ServerNotice.notice(forLanguage:project:)` returns nil the moment
`servers[key].client.isRunning`, and the strip goes away. Nothing on screen said
anything was wrong.

It could not read the project at all. That only surfaced when a *request* was
made — the outline — and the answer came back as an error:

    The rust language server cannot read this project.
    error: custom toolchain 'esp' specified in override file
    '/workspace/esp32/rust-toolchain.toml' is not installed

**The message itself is good.** It names the toolchain, the file, and where the
rest is. The fault is entirely that it waited to be asked.

## Why the app cannot currently tell

Everything the app knows about a server's health is about *starting* it: it is
installed or it is not, the image is here or it is being fetched, the handshake
answered or it did not. A server that starts and then cannot make sense of what
it was pointed at is in none of those states, and the app has no word for it.

It is not a Rust problem. The same shape is jdtls with a classpath it could not
resolve, gopls outside a module, clangd with no `compile_commands.json` — all of
them start, all of them answer the handshake, and all of them then know nothing.
0450 measured the Java version of this from the other end: jdtls silent at 601
seconds *never says it failed*.

## Where the evidence already is

Two places, both already arriving and neither consulted:

- **`window/showMessage` and `window/logMessage`.** A server that cannot read a
  project usually says so unprompted, at `error` level, seconds after
  initialising. Today those go to `lsp.log` — which is where this one was found.
- **The first request that fails.** By then somebody is already looking at a
  question that did not get answered, which is exactly the moment the strip
  should have been there instead.

## Worth deciding

- **What the strip says, and for how long.** "Started but not working" is a
  third state beside "starting" and "not installed", and it needs a sentence
  that does not read as a crash — the server *is* running and the next project
  may be fine.
- **Whether an error message is enough to declare a server unhealthy.** Servers
  log errors that are not fatal. A rule of "any error within N seconds of
  initialising" would be wrong for a busy server and right for this one; whether
  to trust the first failing *request* instead is the alternative.
- **How this meets 0460.** A server that is running but useless is a candidate
  for the thing 0460 built — reconsidering when a preference changes — and
  somebody who fixes the toolchain should not have to reopen the project.

## What was found, and what was ruled out

**The evidence the item expected to be arriving mostly is not.** The plan was to
read `window/showMessage` and `window/logMessage` at error level, which are
already parsed and already logged. Measured, on this machine:

- The `rust-analyzer` image this repository builds reports a project it could
  not load at **level 2, a warning** — "Failed to read Cargo metadata with
  dependencies for `/workspace/Cargo.toml`", then "cargo check failed to start".
  Its **level 1** messages are things like `duplicate DidOpenTextDocument`,
  which costs nothing. The level sorts these exactly the wrong way round.
- `gopls` opened on a `.go` file outside any module said nothing at all in fifty
  seconds; it treats a lone file as an ad-hoc package.
- 0450 already recorded that jdtls silent at 601 seconds never says it failed.
- And in the reproduction on this machine the diagnosis arrives on **standard
  error** and nowhere else, because the process exits before the handshake.

So the message is a weaker signal than the item assumed, and the two states that
carry the weight in practice are the server that stopped and the request that
failed.

**Ruled out: asking the server a question and reading an empty answer as proof.**
This was the plan for confirming a report without waiting to be asked, and it
does not work. Driven by hand against the built image: a project whose
`Cargo.toml` names a crate that does not exist makes rust-analyzer complain
twice — and then answer `textDocument/documentSymbol` and `workspace/symbol` for
45 seconds *exactly as it answers for a project that loads*, because it indexes
the crate from source and only the dependencies are missing. Both projects gave
7, 1, 1 and 2 items for the same four queries. A probe would have called that
server broken.

**Ruled out: waiting for the server to say it has finished, through `$/progress`.**
The idea was to avoid a timer by asking only once the last outstanding progress
token ended. Measured, rust-analyzer's tokens are fine-grained enough that the
outstanding count reaches zero six times during a load — the first at 6.3
seconds, before `cargo metadata` had run at all. "Nothing outstanding" is not
"finished".

**Ruled out: any error within N seconds of initialising**, which the item
already doubted and which the measurements above settle: for the one server
there is a real reproduction for, the fatal message is not an error and the
errors are not fatal.

**What was built instead**: two readings of the same evidence. A message at
error level puts the server's own words on screen as a *report* — it is running,
it complained, here is what about — and any answer with content in it takes that
back within seconds, which is what a busy server that logged something
survivable does. The stronger sentence, that it cannot read the project, needs
the report *and* a question it could not answer. A server that is not running at
all skips both: it has already proved it.

**What was seen on screen**, with the built image and the real project:

- `opentherm-wolf-cwl`, file `esp32/src/main.rs` — the strip, at 10, 25 and 40
  seconds: *rust-analyzer is not running for this project.*, with "What it said"
  carrying `error: custom toolchain 'esp' specified in override file
  '/workspace/esp32/rust-toolchain.toml' is not installed`. The screenshot is in
  `images/`.
- A Rust project the same server reads fine — no strip, at 10, 25 and 40
  seconds.
- The project whose `Cargo.toml` cannot be resolved, where the server complains
  twice and goes on answering — **no strip**, which is the whole of not crying
  wolf.

**A limit, deliberately.** "Ignore for Rust" still silences this, because the
strip is asked for with the ignore list and that guard is at the top of
`notice(forLanguage:project:)`. Somebody who has said they do not want a Rust
server is not told that the Rust server they are not being offered is not
answering. Left alone rather than quietly redefining what that button means.

**A limit that is not deliberate.** The `reported` and `cannotRead` sentences
were exercised in tests and by driving the protocol by hand, and **were not seen
on screen with a real server**, because no server on this machine produced a
level-1 message about a project it could not read in the time this took. The
state that was seen on screen, against the real project, is the one the
reproduction produces.

## Estimate

2026-08-11 10:41 — about twenty minutes left

## Steps

- [x] The app notices a server that has started and cannot read the project,
      from what the server says rather than from a request nobody made
- [x] The strip says so, as a third state, without reading as a crash
- [x] The failing-request path keeps its message, which is already good, and
      stops being the first anybody hears
- [x] Not fooled by a server that logs an error and goes on working
- [x] What a server said is remembered per project rather than per language, or
      one project's broken toolchain makes every other one of that language look
      broken for the session
- [x] A server that started and then *stopped* says so too — which is what the
      reproduction on this machine actually produces
- [x] Watch it happen against the real project, rather than only in a test
- [x] Write down here what was ruled out on the way
- [x] `spec/language-servers.md` says what the project now does
