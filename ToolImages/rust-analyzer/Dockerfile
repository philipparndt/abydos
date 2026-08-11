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
# channel** they do not and cannot: `channel = "esp"` means the directory
# `~/.rustup/toolchains/esp` on the machine reading the project, put there by an
# installer of its own, and rustup resolves it by that directory and by nothing
# else. No image reached by name has it, this one included.
#
# Espressif's `esp` toolchain is the sharp end of it, and neither route answers
# it. Not this image, for the reason above. Not a build argument passing the
# channel in, since there is nothing for rustup to install it *from*. Not the
# copy on the machine either: espup builds the fork with
# `rust-analyzer-proc-macro-srv` and *without* rust-analyzer itself, and rustup
# will not add a component to a custom toolchain. And not a mount of the host's
# toolchain, which is `aarch64-apple-darwin` binaries that will not run in a
# Linux container. So there is nothing to add to this file that would change it,
# and what the editor does instead is say so before starting anything — see
# `ToolchainPin` in AbydosKit. 0462.
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
