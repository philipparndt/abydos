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

## Ruled out

Nothing yet — written before the work.

Worth knowing: the workaround that exists today is Running Servers ▸ **Stop**,
which calls `shutdown(server:)` and is the one path that clears the flag. That is
also a hint at the shape of the fix — the same clearing, reached from a different
event.

## Estimate

2026-08-11 08:37 — about three hours left

## Steps

- [x] A change to where a tool comes from clears what was remembered about it
      failing, per project
- [x] The same for the choice of server, and for the container runtime
- [ ] Decide and record whether a change also starts the server for what is
      already open, or only makes the next open ask
- [x] A running server that is no longer the one asked for is handled, and the
      entry says which way and why
- [x] Driven: a project where a server has failed, a setting changed, and the
      right thing starting without reopening anything
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
