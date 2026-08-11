# 462. A project can pin a toolchain the server's environment has not got

`~/dev/smarthome/projects/opentherm-wolf-cwl/esp32/rust-toolchain.toml` says:

    [toolchain]
    channel = "esp"

Espressif's fork, for ESP32. The image `ToolImages/rust-analyzer/Dockerfile`
builds is `FROM rust:1.97-bookworm` with `rustup component add rust-analyzer
rust-src` — stock Rust and nothing else. So rust-analyzer in the container reads
the override, looks for a toolchain that is not there, and refuses the project.

**And the host cannot answer it either**, which is the part that makes this an
item rather than a support question: `~/.rustup/toolchains/esp/bin/` has `cargo`,
`cargo-clippy`, `rust-gdb` — and **no `rust-analyzer`**. Espressif does not ship
one. So "use the installed copy instead" is not a workaround for this project;
neither route works as things stand.

## The general shape, which is worth more than the Rust case

**A toolchain image fixes the toolchain when the image is built. A project pins
its toolchain when the project is opened.** Those two facts meet at the moment
somebody opens a file, and nothing reconciles them.

It is not only Rust:

- `rust-toolchain.toml` — this.
- `go.mod`'s `toolchain` directive, and `GOTOOLCHAIN`.
- `.sdkmanrc`, `.java-version`, and a `pom.xml`'s `maven.compiler.release`. 0401's
  jdtls image already carries the Java it happens to carry, and 0450 measured
  jdtls resolving a classpath by *running Maven*, which fetches what it lacks —
  so Java hides this for now by doing work at run time that Rust does at build
  time.
- `clangd` and a `compile_commands.json` naming a compiler that is not there,
  which 0401 already noted and worked around by driving clangd's fallback.

## What can actually be done, and none of it is obvious

- **Say so, and mean it.** The message today is good and arrives late (0461). A
  project pinning a toolchain the image has not got is knowable *before* the
  server starts — the file is right there in the project — and could be a
  sentence at the moment somebody chooses the image rather than a failure
  afterwards.
- **Mount the host's toolchains.** 0457's `outside` mechanism is exactly the
  shape, and **it cannot work here**: `~/.rustup/toolchains/esp` holds
  aarch64-apple-darwin binaries, which will not run in a Linux container. Worth
  writing down so nobody spends an afternoon on it.
- **A recipe that takes the toolchain as an argument.** The image is already
  named from the Dockerfile's hash, so a build argument is a different image and
  the naming still holds. Whether a project can ask for one, and where it would
  say so, is the design question.
- **Accept that some projects are host-only**, and make that easy to say. 0449
  and `.abydos/tools.json` already let a project choose its server and where it
  comes from; the missing piece is the app *suggesting* it when the pin and the
  image disagree.

## Ruled out

Nothing yet — written before the work. But the esp case above is a real
constraint on any answer: for this project, no image this repository can
reasonably ship will contain a `rust-analyzer` that Espressif does not publish.

## Steps

- [ ] Read a project's toolchain pin, for Rust at least, before a server starts
- [ ] Say plainly when the pin and the chosen image disagree, at the moment the
      image is chosen rather than at the first failed request
- [ ] Decide whether a recipe can take a toolchain as a build argument, and
      where a project would ask for one
- [ ] Record, in the Rust recipe itself, that a project pinning a custom channel
      cannot use it, so the next person does not rediscover it
- [ ] Write down here what was ruled out on the way
- [ ] `spec/tool-images.md` says what the project now does
