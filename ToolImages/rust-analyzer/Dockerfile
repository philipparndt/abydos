# rust-analyzer, and the Rust toolchain it reads a project through.
#
# This is the image the editor starts when a project names it for
# `rust-analyzer`, and it is what the tool catalogue's contract describes: the
# server on the entry point, speaking the protocol on standard input and
# output, saying nothing before the first header, with the project mounted at
# /workspace.
#
# On the Rust base image rather than a slim one with a release binary copied
# in, for gopls's reason and one more of its own. rust-analyzer runs
# `cargo metadata` to find out what the crates in a workspace are, and one with
# no cargo beside it starts, answers the handshake, and then knows nothing —
# the failure that reads as "the editor is broken" rather than as "the image is
# missing a toolchain". The one of its own: the server and the compiler are
# released together, and a rust-analyzer newer than the `rustc` it is asked
# about is how a project gets diagnostics for syntax its own compiler accepts.
#
# **The toolchain being fixed here is also the limit of what this image can
# read, and it is worth knowing before spending an afternoon on it.** It is
# decided when the image is built; a project pins its toolchain in
# `rust-toolchain.toml`, which is read when the project is opened. Where the pin
# names a *release* the two reconcile themselves — rustup below fetches `1.90.0`
# or `nightly-2025-01-01` when it is asked for one, so a pinned release is
# slower on the first request and is not broken. Where it names a **custom
# channel** this image does not answer it: `channel = "esp"` means the directory
# `~/.rustup/toolchains/esp` on the machine reading the project, put there by an
# installer of its own, and `rustup toolchain install esp` has nothing to install
# it from. That is the sentence this file proves, and it is the only one.
#
# **What this file used to say next was too strong, and 0466 measured it.** It
# said that no image reached by name has the `esp` toolchain, that the copy on
# the machine cannot answer it either, and therefore that there was nothing to
# add to this file that would change it. All three are wrong, and the third
# would cost somebody an afternoon:
#
#   * `espressif/idf-rust:esp32_<version>` has the fork in it, published for
#     `linux/arm64` as well as `linux/amd64` and built by `esp-rs/rust-build`.
#     Pulled and inspected: `~/.rustup/toolchains/esp` is there and is the
#     default toolchain. `espup` also installs inside a container — it downloads
#     a prebuilt Linux fork, which is a different act from asking rustup for a
#     channel it has never heard of.
#   * **The pin does not decide which rust-analyzer runs.** It decides which
#     `cargo` and `rustc` read the project, which is right and wanted. The server
#     is an ordinary program that shells out to the pinned toolchain, so any
#     recent one reads the project. Measured against the project this came from:
#     a stable 1.95 rust-analyzer resolved the sysroot into
#     `~/.rustup/toolchains/esp/lib/rustlib/src` and expanded
#     `#[derive(Serialize)]` out of a dylib the fork's own `rustc` had compiled.
#   * So the missing piece was never the toolchain. It is that **the fork ships
#     no rust-analyzer** — `libexec/rust-analyzer-proc-macro-srv` and nothing in
#     `bin/` — **and every route reached the server through a rustup proxy that
#     insists on getting it from the pinned toolchain**, which inside such a
#     project says:
#
#         error: 'rust-analyzer' is not installed for the custom toolchain 'esp'.
#
#     A *path* instead of a name is the whole of the fix, and a project or a
#     person can now write one down: `{"rust-analyzer": {"command": "…"}}` in
#     `.abydos/tools.json`, or the Executable field in Settings ▸ Tools. See
#     `LanguageServerOverrides` in AbydosKit, and `ToolchainPin`, whose notice
#     above the file now offers this rather than closing the subject.
#
# Two things do stay ruled out. A **mount of the host's toolchain** into a Linux
# container: `~/.rustup/toolchains/esp` is `aarch64-apple-darwin` binaries.
# And **`rustup component add` on a custom toolchain**, which rustup refuses by
# design and says so.
#
# This recipe is not the place for any of it: an esp image is a gigabyte of
# Espressif's base and would be paid for by every Rust project on the machine to
# serve the one that pins the fork. `ToolImages/rust-analyzer-esp/Dockerfile` is
# beside this one for that project, and it is a separate file for exactly that
# reason. 0462, 0466.
FROM rust:1.97-bookworm

# From rustup rather than from the project's GitHub releases, which is the other
# way to get it. The releases are one file and would make a much smaller image,
# and that is exactly the image described above: it would still need the
# toolchain underneath, and then the server's version and the compiler's would
# be two decisions instead of one.
#
# `rust-src` with it, because the standard library is source that is not in the
# toolchain by default: without it, going to the declaration of anything in
# `std` lands nowhere, which looks like the mapping between this machine and the
# container being wrong rather than like a component being absent.
RUN rustup component add rust-analyzer rust-src

# rust-analyzer builds proc macros and downloads the crates a manifest names, so
# it wants somewhere to put them. Both live in the image, as caches and not as
# state: an empty one costs time and nothing else.
ENV CARGO_HOME=/usr/local/cargo
ENV CARGO_TARGET_DIR=/tmp/rust-analyzer-target

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
WORKDIR /workspace

# No arguments: rust-analyzer with no subcommand is the language server on
# standard input and output. A wrapper script here would be the one thing that
# breaks the contract — anything it printed would arrive where the first header
# should be.
ENTRYPOINT ["rust-analyzer"]
