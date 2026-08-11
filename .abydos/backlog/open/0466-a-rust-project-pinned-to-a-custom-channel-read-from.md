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

## Steps

- [ ] A project can name the executable for a server, not only the image —
      absolute path, honoured by `executable(for:)`, which already handles it
- [ ] Prove or disprove the proc-macro leg before building anything else:
      stable rust-analyzer + `procMacro.server` in the esp toolchain, against
      the real project
- [ ] Per-project `initializationOptions`, if the leg above holds
- [ ] A recipe for the image route, if the leg above holds — entry point an
      absolute path, and a comment saying why it is not the shim
- [ ] Correct `ToolImages/rust-analyzer/Dockerfile`, whose claim that nothing
      could change it is what this item disproves
- [ ] 0462's notice offers whichever of these turns out to work, instead of
      saying there is nothing to be done
- [ ] Write down here what was ruled out on the way
- [ ] `spec/tool-images.md` and `spec/language-servers.md` say what the project
      now does
