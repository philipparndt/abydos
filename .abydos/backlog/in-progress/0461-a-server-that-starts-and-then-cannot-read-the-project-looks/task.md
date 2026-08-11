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

## Steps

- [ ] The app notices a server that has started and cannot read the project,
      from what the server says rather than from a request nobody made
- [ ] The strip says so, as a third state, without reading as a crash
- [ ] The failing-request path keeps its message, which is already good, and
      stops being the first anybody hears
- [ ] Not fooled by a server that logs an error and goes on working
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
