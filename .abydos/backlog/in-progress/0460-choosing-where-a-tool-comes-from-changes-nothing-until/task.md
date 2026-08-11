# 460. Choosing where a tool comes from changes nothing until something restarts

Reported from use, and reconstructed from `~/Library/Logs/Abydos/lsp.log`
afterwards:

1. A Rust project opened. `rust-analyzer` started from `~/.cargo/bin/rust-analyzer`,
   which is a rustup shim for a component that is not installed, and answered
   `error: Unknown binary 'rust-analyzer' in official toolchain` before exiting.
2. `LanguageService` recorded it as `unavailable` for that project. Its own
   comment says why: *"Not tried again for this project: a name that is wrong is
   wrong every time… Reopening the project asks again."*
3. Settings ▸ Tools ▸ rust-analyzer was then set to build the image on this
   machine. The preference was written correctly —
   `toolImages = { "rust-analyzer" = build; }`.
4. **Nothing happened.** No container, no build, no message. The log's last line
   is from before the choice was made.

The setting is right, the resolution is right, and the two never meet, because
`unavailable` is only ever cleared in `shutdown(server:)`. Nothing about a
*preference changing* reconsiders a server that has already failed.

**A stored preference that changes nothing until you restart something is worse
than one that was not stored**, because it looks like it worked. There is no
error to read and nothing on screen disagrees with what was asked for.

## What has to change

`unavailable`, `failures` and `missingHints` are a memory of an answer given
under conditions that have now changed. The conditions worth reacting to:

- **Where a tool comes from** — `Settings.toolImages`, and `.abydos/tools.json`,
  which `images(for:)` merges. This is the case that was reported.
- **Which server a language uses** — 0449's `languages` section, the same shape
  one question along. A project that switches from jdtls to kmp-lsp after jdtls
  has failed would be stuck the same way.
- **The container runtime preference**, since "nothing here can run a container"
  is remembered as a failure too, and choosing a runtime that *is* installed
  should undo it.

`toolImages` is already dropped per project by `stop(for:)`, so the shape exists;
what is missing is anything calling it when a preference changes rather than when
a project closes.

## Worth deciding

- **How far to go.** Clearing the memory is enough to make the *next* file ask
  again — but somebody who has just chosen an image is looking at the editor and
  expecting something to happen now, not on the next open. Whether a change also
  *starts* the server for what is already on screen is the real question, and it
  is the difference between "it works when I go back to the file" and "it works".
- **A running server that is now the wrong one.** If a project is using the
  installed copy and the setting changes to an image, the running one is no
  longer what was asked for. Stopping it and starting the other is the honest
  reading, and it is also the more disruptive one — jdtls's import is minutes.
  Say which, and why.
- **Not turning this into a restart on every keystroke in Settings.** A text
  field for a custom image name changes on every character; whatever watches has
  to react to a settled value.

## What was decided

- **It starts, it does not only unblock.** An affected project is warmed up as
  though it had just been opened, and every file on screen is announced again
  through `.ideaiLanguageServersMoved` — the notification a project moving in or
  out of its devcontainer already sends, and it does exactly this job. Clearing
  the memory alone would have been the same fault with a longer fuse: somebody
  who has just chosen an image goes looking for what is wrong long before they
  next open a file of that language, and "it works when you go back to the file"
  is indistinguishable from "it does not work" for as long as they are looking.
- **A running server that is no longer the one asked for is stopped.** The
  disruptive reading, chosen for three reasons. The spec already says a project
  holds one server for a language and no more, because two answering over one
  file is two sets of diagnostics with no rule for which wins; what the old one
  goes on publishing is a toolchain the project has stopped using, which is
  0432's fault; and jdtls's minutes are the cost of the choice just made, paid
  while the person is looking at the thing they changed rather than at some later
  moment they cannot connect to it. It goes through `shutdown(server:)` — the
  Stop button's own path, which is where this entry said the shape of the fix
  was.
- **The blast radius is per project and per server.** `ServerReconsideration`
  works out what one project has to forget and what of it to stop, from the
  merged choices and images before and after. So a project whose own
  `.abydos/tools.json` answers the question is untouched when the setting behind
  it moves; an image chosen for a renderer does not re-import a Java project; and
  a project with nothing to do is not even walked. Getting this set wrong in
  either direction was the whole risk, so it is in AbydosKit with eighteen tests
  on it rather than inline in the reaction.
- **Coalesced over 400ms rather than debounced per control.** The custom-image
  field the entry warns about sends its action when the editing ends rather than
  per character, so today's controls settle by themselves — but a preference
  change costs a server being stopped and started, and that is not a bill to
  leave resting on a control's configuration. An empty image is also refused as
  a change in its own right, which is the other half of the same trap: the popup
  writes one the moment "Custom" is picked, before anybody has typed a name.

## Ruled out

- **Clearing everything and warming every project up.** It is two lines and it is
  wrong: somebody choosing an image for PlantUML would restart the Java server in
  a project they have not looked at since this morning, and the re-import is
  minutes. What is affected is a question with a real answer, so it is answered.
- **Watching `.abydos/tools.json` on disk.** `images(for:)` merges the project's
  file with the settings, and the merged answer is read again here — but only
  when a *setting* changes. A project's own file edited in the editor still needs
  the project reopened. That is a second mechanism (a watcher, and a decision
  about what an editor saving its own project's file every fifteen seconds should
  cost), and it is not what was reported. Left undone knowingly.
- **Reacting to `.abydosSettingsChanged` directly.** One notification is posted
  for every setting written and it says nothing about which one, so anything
  reacting to it reacts to the appearance slider too. Holding the three
  preferences as a value and comparing is what makes the reaction specific — and
  it is also what makes an empty image, or a setting written back unchanged, not
  a change.

Worth knowing: the workaround that existed before this was Running Servers ▸
**Stop**, which calls `shutdown(server:)` and was the one path that cleared the
flag. That was also the hint at the shape of the fix, and it is the call this
now makes.

## What it looked like when driven

`~/.cargo/bin/rust-analyzer` on this machine is a rustup shim for a component
that is not installed, so the fault reproduces without inventing one. All three
conditions were driven against the built app under a throwaway bundle identifier,
with `--choose-setting "Page/Row=value@seconds"`, which sets a value through the
settings row's own setter while the app is running.

Where a tool comes from — an image chosen for a server that had already failed:

    08:54:05 rust-analyzer started … [/Users/philipparndt/.cargo/bin/rust-analyzer]
    08:54:06 rust-analyzer stderr: error: Unknown binary 'rust-analyzer' …
    08:54:06 rust-analyzer handshake failed: The language server is not running.
    08:54:17 rust-demo: a preference changed — 1 server(s) reconsidered, 0 stopped
    08:54:17 rust-analyzer comes from pharndt/abydos-rust-analyzer:dev; …
    08:54:17 rust-analyzer started for rust … [container run …]
    08:54:17 rust-analyzer was told about 1 file(s) opened while its image …
    08:54:18 rust-analyzer initialized

Which server answers — Java pointed at the other one while jdtls was running:

    09:04:29 jdtls started for java … [/opt/homebrew/bin/jdtls]
    09:04:34 jdtls initialized
    09:04:55 jdtls was stopped because a preference changed for java-demo
    09:04:55 java-demo: a preference changed — 2 server(s) reconsidered, 1 stopped
    09:04:55 kmp-lsp is not installed — java in java-demo has no server. …

Two reconsidered and one stopped: both keys, because the server is filed under
its own name and the project moved from one to the other. Nothing was started in
kmp-lsp's place, which is the rule the spec already had.

The container runtime — docker's daemon was down on this machine, so the fetch
had already failed under it:

    09:02:58 rust-analyzer: The container runtime is not running, so
             pharndt/abydos-rust-analyzer:dev could not be fetched.
    09:03:16 rust-demo: a preference changed — 1 server(s) reconsidered, 0 stopped
    09:03:16 rust-analyzer started for rust … [container run …]

And the other direction, which is the stop: a server running from an image, the
setting put back to the copy installed here, the container's server stopped and
the installed one tried and failing honestly.

    09:00:26 rust-analyzer was stopped because a preference changed for rust-demo
    09:00:26 rust-demo: a preference changed — 1 server(s) reconsidered, 1 stopped
    09:00:26 rust-analyzer started for rust … [/Users/…/.cargo/bin/rust-analyzer]
    09:00:26 rust-analyzer handshake failed: The language server is not running.

Nothing was reopened in any of them, and no container was left behind.

**Not proved.** Nothing here was driven with the project's own
`.abydos/tools.json` in play — that a project pinning its own answer is untouched
is a test rather than a photograph. And the toast a person would see is only in
the log here: what was watched was `~/Library/Logs/Abydos/lsp.log` and the list
of running servers, not the corner of the window.

## Estimate

2026-08-11 09:07 — about half an hour left

## Steps

- [x] A change to where a tool comes from clears what was remembered about it
      failing, per project
- [x] The same for the choice of server, and for the container runtime
- [x] Decide and record whether a change also starts the server for what is
      already open, or only makes the next open ask
- [x] A running server that is no longer the one asked for is handled, and the
      entry says which way and why
- [x] Driven: a project where a server has failed, a setting changed, and the
      right thing starting without reopening anything
- [x] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
