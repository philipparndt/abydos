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

## What was found

**Espressif publishes no rust-analyzer anywhere, and this was checked rather
than assumed.** The releases of `esp-rs/rust-build` — `v1.97.0.0`, the version
of the toolchain on this machine — carry five assets, four host tarballs and
`rust-src`, and no rust-analyzer among them. The fork is built with
`--tools=clippy,cargo,rustfmt,rust-analyzer-proc-macro-srv,src`: the *proc-macro
server* is in it and the language server is not, which is exactly what
`~/.rustup/toolchains/esp/` holds here — `libexec/rust-analyzer-proc-macro-srv`
and nothing in `bin/`. `esp-rs/espup#254` asked for the server to be shipped and
is closed without it; the workaround people use is to point their editor at some
*other* rust-analyzer binary, which works because rust-analyzer shells out to
`cargo` and the override then decides which cargo. That is a real route and it
is not one rustup will take, because `rust-analyzer` on the PATH is rustup's own
proxy and the proxy refuses a component a custom toolchain has not got.

So the shape of the item stands as written. Neither route answers that project,
and no amount of work here changes it.

**Both sentences were driven against the real project**, not only against a
temporary directory. `--open ~/dev/smarthome/projects/opentherm-wolf-cwl --file
esp32/src/config.rs --lsp-banner report`, on a build of this branch, says:

    This project pins the Rust toolchain ‘esp’, and the copy of it on this
    machine has no rust-analyzer in it, so nothing here can read the project.

and with `rust-analyzer` set to come from an image:

    This project pins the Rust toolchain ‘esp’, which is installed by name on a
    machine and is in no image, so rust-analyzer will start and then answer
    nothing about it.

`images/the-strip-on-the-esp-project.png` is the first of those above the file.
The old failure is still visible underneath it in the earlier of those runs —
the "rust-analyzer did not answer" toast, arriving seconds later, which is what
this replaces as the first thing anybody hears.

**The state before a server starts is worth more than it looks.** Everything
needed to know this project cannot be read is on disk: the channel is in a file,
the image's toolchain was decided when the image was built, and whether the
installed copy has the server is a directory listing. None of it needs a
container, a process or a handshake — which is why `ToolchainPin` is in
AbydosKit with no view code near it and is tested by thirteen tests that start
nothing.

## Ruled out

- **Mounting the host's toolchain through 0457's `outside`.** As the item said:
  `~/.rustup/toolchains/esp` is `aarch64-apple-darwin` binaries and the
  container is Linux. Not attempted.
- **A build argument for the toolchain, for now.** It would work, and the
  condition on it is what was worth establishing rather than the answer: the
  built image is named `abydos-built/<tool>:<fingerprint of the build context>`,
  so an argument that is not *in* the fingerprint gives two different images one
  name and the next project silently gets the last one's. Hashing the arguments
  beside the files is a few lines and the naming holds again, and
  `.abydos/tools.json` has the room to ask for one — its object shape,
  `{"tool": {"image": …}}`, was added for exactly this kind of thing.

  What is missing is a use. A pinned *release* already works, because rustup
  inside the image fetches a release it has not got; a pinned *custom channel*
  cannot be built at all, because there is nothing to install it from whatever
  the argument says. So the mechanism would cost a full toolchain image per
  project and answer neither half of the case that raised it. Written down in
  `ToolImageRecipes.build` where somebody would go to add it, with the
  fingerprint condition, so the next person starts from the condition rather
  than from the idea.

- **Reading Go's and Java's pins as well.** Deliberately not done, and the
  reason is a finding rather than a shortage of time: `go.mod`'s `toolchain`
  directive names a release the `go` command downloads for itself, and jdtls
  resolves a classpath by running Maven, which fetches what it lacks — 0450
  measured that. Neither fails today, so a reader for either would say sentences
  about a failure nobody has seen, which is what `ToolImageCatalogue`'s rule
  about known-good images exists to prevent. `ToolchainPin` is per tool so that
  the day one of them does fail its reader goes beside Rust's; the comment there
  says which and why.

- **A pinned release being worth a sentence.** It is not. The image's rustup
  fetches it, so the first request is slower and nothing is broken, and a strip
  over every pinned Rust project on the machine is a strip nobody reads by the
  end of the week. `objection` returns nil for a release whatever it is coming
  from, and there is a test that says so.

## What is left

- **Nothing suggests the fix, it only says it.** The strip names the installed
  copy in its details and does not offer a button that switches to it. The
  `ServerNotice.Offer` mechanism is right there and would fit — but for the
  `esp` case the offer would be wrong, since the installed copy has no
  rust-analyzer either, and an offer that has to be right about *this machine*
  before it appears is more than this item needed. The last bullet of "what can
  actually be done" above is therefore half done: it is easy to say, and it is
  not suggested.
- **The pin is read once per project**, like the images beside it, so editing
  `rust-toolchain.toml` while the project is open does not change what the strip
  says until the project is opened again.

## Steps

- [x] Read a project's toolchain pin, for Rust at least, before a server starts
- [x] Say plainly when the pin and the chosen image disagree, at the moment the
      image is chosen rather than at the first failed request
- [x] Decide whether a recipe can take a toolchain as a build argument, and
      where a project would ask for one
- [x] Record, in the Rust recipe itself, that a project pinning a custom channel
      cannot use it, so the next person does not rediscover it
- [x] Write down here what was ruled out on the way
- [x] `spec/tool-images.md` says what the project now does
