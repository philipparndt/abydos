# 466. A Rust project pinned to a custom channel, read from somewhere

0462 made the app say clearly that `~/dev/smarthome/projects/opentherm-wolf-cwl`
pins `channel = "esp"` and that nothing can read it. The sentence is right and it
is where this item starts. **But two of the reasons it gives are stronger than
the facts, and both routes it closes are actually open.**

`ToolImages/rust-analyzer/Dockerfile` says it in the sharpest form: *"there is
nothing to add to this file that would change it"*. There is.

## What was measured, on this machine

    ~/.rustup/toolchains/          esp, stable-aarch64-apple-darwin
    ~/.rustup/toolchains/esp/bin/  cargo cargo-clippy cargo-fmt clippy-driver
                                   rust-gdb rust-gdbgui rust-lldb rustc
                                   rustdoc rustfmt
    ~/.rustup/toolchains/esp/libexec/  rust-analyzer-proc-macro-srv
    ~/.cargo/bin/rust-analyzer     -> rustup        (a symlink; byte-identical
                                                     to ~/.cargo/bin/rustc)

and run inside the project:

    $ ~/.cargo/bin/rust-analyzer --version
    error: 'rust-analyzer' is not installed for the custom toolchain 'esp'.

**That is a different error from the one in the notice**, and the difference is
the whole item. The notice quotes rustup failing to find the toolchain
*directory* — which is what happens in the container, where `esp` genuinely is
not installed. Here the toolchain is installed and rustup is refusing to hand
over a *component* of it. There is no rust-analyzer on this machine at all: the
thing on the `PATH` is a rustup proxy, and a proxy inside this project resolves
through `rust-toolchain.toml` to `esp` and stops.

## Where the reasoning was too strong

**"The pin can only be answered by the machine's own toolchain."** — Not quite.
The pin decides which `cargo` and `rustc` read the project, and that is right.
It does not decide which *rust-analyzer* binary runs: the server is an ordinary
executable that shells out to the pinned toolchain. Any rust-analyzer will do,
as long as it is reached by an absolute path rather than through the proxy.

**"No image reached by name has it."** — Espressif publishes
`espressif/idf-rust`, `linux/arm64` as well as `linux/amd64`, tagged
`<chip>_<version>` (`esp32_latest`, `esp32_1.64.0.0`), built by `esp-rs/rust-build`
and containing the Xtensa fork. `espup` also installs it inside a container: it
downloads a prebuilt Linux fork, so there *is* something for it to install from —
the thing there is nothing to install from is `rustup toolchain install esp`,
which is the sentence the Dockerfile actually proves.

So the missing piece was never the toolchain. It is that **the esp toolchain has
no rust-analyzer in it, and both routes reach rust-analyzer through a proxy that
insists on getting it from there.**

## The two routes, and what each needs

**The installed copy, which needs no container at all.** Put a real binary on
this machine — `rustup component add rust-analyzer --toolchain stable` gives
`~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/rust-analyzer` — and point
the project at *that path*, not at the name. `cargo` and `rustc` still resolve to
`esp` through the pin, which is what should happen.

**An image whose recipe knows about this.** `FROM espressif/idf-rust:esp32_…`,
or `FROM rust` plus `espup install`; rust-analyzer and `rust-src` from the stable
toolchain; and the entry point the **absolute path** to that binary rather than
`rust-analyzer`, which in this image would be a shim that asks `esp` for a
component it has not got. That last line is the one that makes it work and the
one that is easy to get wrong, because the current recipe's `ENTRYPOINT
["rust-analyzer"]` is correct for every other Rust project and wrong only here.

## What is not verified, and is the risk

**Proc macros.** `esp-rs/espup#254` is closed with nothing shipped, and the
workaround it records — linking rust-analyzer in from another toolchain — is
documented as incomplete precisely because the analyzer cannot load `.so` proc
macros built by a forked compiler. Espressif ships
`libexec/rust-analyzer-proc-macro-srv` in the esp toolchain for exactly this, and
rust-analyzer's `procMacro.server` setting is where it goes. **Nobody here has
run that combination.** It may be that everything except macro expansion works,
which for embedded code is a great deal less useful than it sounds, since
`esp-idf-hal` leans on macros. Find out early — it decides whether this item is
worth finishing.

## The proc-macro leg holds. It was the risk and it is answered.

Measured before anything was built, because it decides whether the rest is worth
building. It is worth building.

`rustup component add rust-analyzer --toolchain stable` — **run against this
machine's own toolchains**; it is additive and
`rustup component remove rust-analyzer --toolchain stable` undoes it — put a real
binary at
`~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/rust-analyzer`,
`rust-analyzer 1.95.0 (59807616 2026-04-14)`. It was driven over the protocol by
absolute path, never through the proxy, with the working directory inside a
project pinned to `channel = "esp"`, whose `rustc` is `1.95.0-nightly
(95e5bda86 2026-04-15) (1.95.0.0)`.

**Three things came back, and the third is the one nobody had.**

*The pin decided the toolchain, and the analyzer was not the pin's business.*
Go-to-definition on `Vec` landed in

    ~/.rustup/toolchains/esp/lib/rustlib/src/rust/library/alloc/src/vec/mod.rs

A stable rust-analyzer read the project through Espressif's fork. That is the
claim this item made, and it is now a measurement.

*The workspace loaded, clean.* Against a copy of the real project —
`esp-idf-svc 0.51`, `embuild`, the whole ESP-IDF build script — the server
reached `{"health": "ok", "quiescent": true}`, published **no diagnostics at all**
for `src/scheduler.rs`, and answered `documentSymbol` with every item in the file
including its `tests` module.

*Proc macros expand.* `rust-analyzer/expandMacro` on the `Serialize` in
`#[derive(Debug, Clone, Default, Serialize, Deserialize)]` at
`esp32/src/scheduler.rs:15` returned the whole generated `impl`, with the
`#[serde(rename = "startHour")]` names in it:

    impl _serde::Serialize for ScheduleEntry {
        fn serialize<__S>(&self, __serializer: __S) -> …
            … serialize_field(&mut __serde_state, "startHour", &self.start_hour)?;

The library being expanded, `libserde_derive-*.dylib`, was compiled by the
*fork's* `rustc`. So the thing `espup#254` warns about — a stable analyzer unable
to load proc macros built by a forked compiler — **did not happen**, and the
reason is version proximity rather than luck: the fork is rebased on
1.95.0-nightly and the analyzer is 1.95.0, so the proc-macro bridge ABI is the
same one. That is the condition to remember, not the result. A fork a release or
two behind the analyzer is where this would break, and that is what the setting
below is for.

**`procMacro.server` was not needed, and it does work.** The expansion above was
obtained twice: once with rust-analyzer's own built-in proc-macro server, once
with `procMacro.server` pointed at
`~/.rustup/toolchains/esp/libexec/rust-analyzer-proc-macro-srv`. Identical
answers. The setting was proved *live* rather than ignored by pointing it at a
path that does not exist, which turns the server's health to

    warning — Failed spawning proc-macro server for workspace `…/Cargo.toml`:
    Failed to run proc-macro server from path /nonexistent/…, error: NotFound

and makes every expansion read `Expansion had errors: proc macro server error`.
So it is a real setting and the right place for the fork's own server on the day
the ABIs diverge; today the built-in one is enough. That ordering matters for the
recipe — the **absolute path to the binary** is what makes this work, and
`procMacro.server` is insurance.

**`rust-src` from stable is not needed either.** `~/.rustup/toolchains/esp/`
already carries `manifest-rust-src` and `lib/rustlib/src/rust/library`, which is
why the `Vec` above resolved at all. The esp toolchain is missing exactly one
thing, and it is the server binary.

## What this app is missing either way

`LanguageServers.executable(for:)` honours a `command` containing `/` as a path.
But nothing lets a *project or a person* set that command: `.abydos/tools.json`
and Settings ▸ Tools choose a server and an image, not an executable. So even
route one — install the binary, point at it — cannot be expressed today. Whatever
else this item does, **that is the gap**, and it is small and useful well beyond
Rust: every toolchain manager that puts a proxy on the `PATH` has this shape.

And `LanguageServers.initializationOptions` exists, so `procMacro.server` has
somewhere to go; it needs to be settable per project rather than compiled in.

## Ruled out

- **Mounting the host's `esp` toolchain into a Linux container** — the
  Dockerfile has this right and it stays ruled out. `~/.rustup/toolchains/esp`
  is `aarch64-apple-darwin` binaries.
- **`rustup component add` on a custom toolchain** — rustup refuses by design,
  and says so: *"this is a custom toolchain, which cannot use `rustup component
  add`"*.

## Estimate

2026-08-11 17:51 — about an hour left; both routes driven end to end, tests and spec remain

## Steps

- [x] A project can name the executable for a server, not only the image —
      absolute path, honoured by `executable(for:)`, which already handles it
- [x] Prove or disprove the proc-macro leg before building anything else:
      stable rust-analyzer + `procMacro.server` in the esp toolchain, against
      the real project — **it holds**, both with and without the setting
- [x] Per-project `initializationOptions`, if the leg above holds
- [x] A recipe for the image route, if the leg above holds — entry point an
      absolute path, and a comment saying why it is not the shim
- [x] Correct `ToolImages/rust-analyzer/Dockerfile`, whose claim that nothing
      could change it is what this item disproves
- [x] 0462's notice offers whichever of these turns out to work, instead of
      saying there is nothing to be done
- [x] A recipe nothing can ask for is not a route — `build:<recipe>` names one
      that is not the tool's own, and the pin stops objecting to it
- [ ] Drive the corrected notice against the real project, with the pin in place
- [ ] Write down here what was ruled out on the way
- [ ] `spec/tool-images.md` and `spec/language-servers.md` say what the project
      now does
