# rust-analyzer for a project pinned to Espressif's Xtensa fork.
#
# `ToolImages/rust-analyzer/Dockerfile` is the recipe for every other Rust
# project and this one is only for `channel = "esp"`. Two files rather than one
# because this base is about a gigabyte of Espressif's toolchain, and a single
# recipe would charge every Rust project on the machine for the one that pins the
# fork. Read that file first: it says what a toolchain pin is and why an ordinary
# Rust image cannot answer a custom channel.
#
# ## The one line that matters, and it is the entry point
#
# `ENTRYPOINT ["rust-analyzer"]` — which is correct in the other recipe and in
# every image in the catalogue — is **wrong here**, and wrong in a way that looks
# like the editor being broken. The base image puts `/home/esp/.cargo/bin` first
# on its `PATH`, and `rust-analyzer` there is a symlink to `rustup`. Run inside a
# project pinning the fork it resolves the pin, asks the `esp` toolchain for a
# component the fork does not build, and exits:
#
#     $ container run --rm espressif/idf-rust:esp32_1.95.0.0 rust-analyzer --version
#     error: 'rust-analyzer' is not installed for the custom toolchain 'esp'.
#
# So the entry point is the **absolute path** to a real binary, below. Anything
# on the `PATH` is the proxy.
#
# ## Why a stable toolchain's rust-analyzer reads a fork's project at all
#
# Because the pin is not about the server. It decides which `cargo` and which
# `rustc` read the project — which is the whole point of pinning — and
# rust-analyzer is an ordinary program that shells out to whichever those are. So
# the fork answers every question about the code and a release toolchain supplies
# the one binary the fork does not build.
#
# Measured before this file existed, on macOS against the real project: a stable
# 1.95 rust-analyzer pointed at by path resolved `Vec` into
# `~/.rustup/toolchains/esp/lib/rustlib/src/rust/library/alloc`, reported the
# workspace healthy and quiescent with no diagnostics, and expanded
# `#[derive(Serialize)]` out of a `libserde_derive` the fork's own compiler had
# built. `esp-rs/espup#254` warns that proc macros are where this breaks; it did
# not break, and the reason is version proximity rather than luck — see the
# release pinned below.
#
# ## What is deliberately not here
#
# * **`FROM rust` plus `espup install`.** It works — espup downloads a prebuilt
#   Linux fork, so a container is not a problem for it — and it would rebuild the
#   fork's download on every recipe edit for no gain over a published image that
#   already has it.
# * **A mount of the host's `esp` toolchain.** `~/.rustup/toolchains/esp` on this
#   machine is `aarch64-apple-darwin` binaries. Ruled out in 0462 and still ruled
#   out.
# * **`rustup component add rust-analyzer --toolchain esp`.** rustup refuses a
#   component on a custom toolchain by design and says so.

# The fork, from Espressif, with the chip and the fork's version in the tag.
#
# Pinned rather than `esp32_latest`, because the tag has to agree with the
# release below: a proc macro is a shared library compiled by the *fork's* rustc
# and loaded by the *server*, across an ABI that only holds while the two are
# close. `1.95.0.0` is the fork rebased on 1.95.0-nightly, and the release below
# is 1.95.0. Moving one without the other is how macro expansion stops working
# while everything else keeps answering — which is the least obvious failure this
# whole file is trying to avoid.
#
# `esp32` is the chip. Espressif publish a tag per chip because the tag decides
# which GCC and clang come with it; a project for another one wants
# `esp32s3_1.95.0.0` and the rest of this file unchanged.
FROM espressif/idf-rust:esp32_1.95.0.0

# The release toolchain, for the one binary the fork does not build.
#
# `--profile minimal` and one component: the default profile would add a second
# `clippy` and `rustfmt` nobody here will run. **And no `rust-src`**, which the
# other recipe does install and which would be wasted here: the fork ships its
# own (`manifest-rust-src`, `lib/rustlib/src/rust/library`) and the server reads
# the sysroot the *pin* resolves to, not its own. Measured — go-to-declaration on
# `Vec` from this project lands in `~/.rustup/toolchains/esp/lib/rustlib/src`.
#
# The symlink is what makes an entry point nameable at all. The toolchain
# directory carries the host triple in its name — `1.95.0-aarch64-unknown-linux-gnu`
# here, something else on an amd64 machine — and an `ENTRYPOINT` is a literal with
# no shell to expand anything, so the path is worked out at build time and the
# entry point names the fixed one. A symlink and not a wrapper script: a script is
# the one thing that breaks the protocol contract, since anything it printed would
# arrive where the first header should be.
#
# As `esp`, the image's own user, and this matters twice. rustup keeps its
# toolchains under that user's home, so the same command as root installs into a
# `RUSTUP_HOME` nothing else can see — and, worse, sets *its* default toolchain
# rather than leaving `esp` the default, which is the answer this whole image
# depends on for `cargo` and `rustc`. The symlink therefore goes into that home as
# well, where `esp` can write, rather than into `/opt` where it cannot.
RUN rustup toolchain install 1.95.0 --profile minimal --component rust-analyzer \
 && ln -s "$(rustup run 1.95.0 rustc --print sysroot)/bin/rust-analyzer" \
          /home/esp/rust-analyzer \
 && test -x /home/esp/rust-analyzer \
 && test "$(rustup default)" = "esp (default)"

# What the fork's build scripts need, which `~/export-esp.sh` sets for a login
# shell and nothing sets for a process on a pipe.
#
# `esp-idf-sys` builds ESP-IDF from source through cmake and needs the Xtensa
# GCC on the `PATH` and libclang for bindgen. Set as environment rather than
# sourced, for the reason the symlink above is a symlink: there is no shell in
# front of this server, and there must not be.
ENV LIBCLANG_PATH=/home/esp/.rustup/toolchains/esp/xtensa-esp32-elf-clang/esp-20.1.1_20250829/esp-clang/lib
ENV PATH=/home/esp/.rustup/toolchains/esp/xtensa-esp-elf/esp-15.2.0_20250920/xtensa-esp-elf/bin:/home/esp/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# The fork's own proc-macro server, for the day the ABI above stops holding.
#
# Not set here, and that is a decision rather than an omission. rust-analyzer's
# `procMacro.server` is a *client* setting, so it belongs in the project that
# needs it and not in an image everybody shares — and it was measured to be
# unnecessary today, the built-in server giving byte-identical expansions. When
# the release and the fork drift far enough apart to need it, this is the path,
# named in `.abydos/tools.json`:
#
#     { "rust-analyzer": { "initializationOptions": { "procMacro": {
#         "server": "/home/esp/.rustup/toolchains/esp/libexec/rust-analyzer-proc-macro-srv" } } } }
#
# Pointing it at a path that is not there is visible rather than silent: the
# server reports `health: warning — Failed spawning proc-macro server`, and every
# expansion reads `Expansion had errors`.

# rust-analyzer builds proc macros and downloads the crates a manifest names, so
# it wants somewhere to put them. Both live in the image, as caches and not as
# state: an empty one costs time and nothing else. `CARGO_HOME` is the base
# image's own, since that is where its `cargo` and the fork's registry index
# already are.
ENV CARGO_TARGET_DIR=/tmp/rust-analyzer-target

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
WORKDIR /workspace

# The absolute path, for the reason at the top of this file. `rust-analyzer` here
# would be `/home/esp/.cargo/bin/rust-analyzer`, which is rustup, which asks
# `esp` for a component it has not got — an image that starts, answers the
# handshake and then reports nothing about any file.
ENTRYPOINT ["/home/esp/rust-analyzer"]
