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

## What was built, and what it looked like in the app

**A project or a person can name the executable.** `LanguageServerOverrides`
reads it out of the file the images and the choices already come from:

    { "rust-analyzer": { "command": "~/.rustup/toolchains/…/bin/rust-analyzer" } }

and Settings ▸ Tools has an Executable field per tool beside its Custom image.
The file wins and the setting is the default, as everywhere else out of that file
— but **key by key rather than entry by entry**, which is the one thing here worth
arguing about. A project that names only `initializationOptions` must not take
away a command somebody set for every project, and replacing the entry wholesale
would: the symptom is a server that stops starting because a line about proc
macros was added, and nothing on screen would connect the two.

`~` is expanded on the side where it means this machine's home and left alone on
the side where it means an image's, which is why the expansion is in
`executable(for:)` and not in the reader. **Inside `initializationOptions` nothing
is expanded at all**, and that is a limitation rather than an oversight: those are
one server's settings and this app has no schema for any of them, so guessing that
a leading `~` is a path would be right for `procMacro.server` and wrong for the
first setting whose value legitimately starts with one. A server wanting an
absolute path has to be given one.

**Driven against the real project, with the pin in place.** On a build of this
branch, `--open ~/dev/smarthome/projects/opentherm-wolf-cwl --file …/esp32/src/
scheduler.rs --banner-at 3,6,10,18`, four readings all the same:

    This project pins the Rust toolchain ‘esp’, and the copy of it on this
    machine has no rust-analyzer in it — but rust-analyzer from
    ‘stable-aarch64-apple-darwin’ reads it, if you name that path for
    rust-analyzer rather than letting rustup pick.

The first half is 0462's sentence and is still right. The second half is what this
item added, and behind the button — “What can read it” — the details now end in a
*What to do* section with the line to paste, instead of the paragraph that ended
"there is nothing this editor can do about it".

Then against a copy of that project carrying the `command` and the
`procMacro.server`: no banner at 4, 20, 60 or 120 seconds, and

    LSP: servers=[…, "~/.rustup/toolchains/stable-aarch64-apple-darwin/bin/
    rust-analyzer", …] diagnostics=0 for scheduler.rs

The named path is what started, and the file is clean. (A copy, because the real
project is the user's and rust-analyzer writes to `target/`.)

**The image route, built and driven.** `ToolImages/rust-analyzer-esp/Dockerfile`,
`FROM espressif/idf-rust:esp32_1.95.0.0` — pulled with Apple `container`,
linux/arm64, 973 MiB compressed, and its `~/.rustup/toolchains/esp` is the default
toolchain. Inside it, side by side:

    $ container run --rm <built> --version
    rust-analyzer 1.95.0 (5980761 2026-04-14)
    $ container run --rm --entrypoint rust-analyzer <built> --version
    error: 'rust-analyzer' is not installed for the custom toolchain 'esp'.

which is the one line that makes the recipe work and the one that is easy to get
wrong. Driven over the protocol with the project mounted: `health: ok`,
`quiescent: true`, `Vec` resolving into
`/home/esp/.rustup/toolchains/esp/lib/rustlib/src` **inside the container**, and
the serde derive expanding. Asked for as
`{"rust-analyzer": {"image": "build:rust-analyzer-esp"}}` — a recipe nothing can
ask for is not a route, so `resolve(image:forTool:)` learned that a recipe need not
be the tool's own.

Nothing was pushed anywhere. The image built here was removed afterwards; the
pulled `espressif/idf-rust` was left, since it is what the recipe builds on.

## Ruled out

- **Mounting the host's `esp` toolchain into a Linux container** — the
  Dockerfile has this right and it stays ruled out. `~/.rustup/toolchains/esp`
  is `aarch64-apple-darwin` binaries.
- **`rustup component add` on a custom toolchain** — rustup refuses by design,
  and says so: *"this is a custom toolchain, which cannot use `rustup component
  add`"*.
- **Putting the esp base into the existing `rust-analyzer` recipe.** It would
  work and it would charge every Rust project on the machine a gigabyte of
  Espressif's toolchain to serve the one that pins the fork. Two recipes instead,
  which is what made `build:<recipe>` necessary.
- **`FROM rust` plus `espup install`, for the recipe.** It does work — espup
  downloads a prebuilt Linux fork, so a container is not the obstacle the
  Dockerfile implied — and it rebuilds that download on every recipe edit for no
  gain over a published image that already has it. Written into the recipe as the
  route not taken, since the *fact* that espup works in a container is the part
  that was wrong before.
- **Installing `rust-src` from the release toolchain in the esp recipe.** The
  other recipe does it and here it is wasted: the fork ships its own, and the
  server reads the sysroot the *pin* resolves to rather than its own. Measured, in
  both places — `Vec` lands in `~/.rustup/toolchains/esp/lib/rustlib/src` on the
  machine and in the container.
- **Doing the release install as `root` in the recipe.** Costs an hour if
  attempted: rustup keeps toolchains under a *user's* home, so as root it installs
  into a `RUSTUP_HOME` nothing else can see — and sets that user's default
  toolchain rather than leaving `esp` the default, which is the answer the whole
  image depends on. The recipe installs as `esp` and has a `test` line asserting
  the default is still `esp`.
- **Expanding `~` inside `initializationOptions`.** Above: no schema, so no way to
  know which values are paths.
- **Offering the second recipe in Settings ▸ Tools.** It exists for a property of
  a *project* — which channel it pins — and a person choosing it once would be
  choosing Espressif's toolchain for their ordinary Rust as well.
- **Guessing whether a *stranger's* image knows about the channel.** The pin stops
  objecting for a recipe from this repository, because that is a file whose
  comment somebody can read and shipping it at all is this project's own answer.
  For `some/registry:tag` there is nothing to read, so the objection stands and the
  way to silence it is to name the command — which is what that image needs anyway,
  since `espressif/idf-rust` puts the proxy first on its `PATH`.

## Left over

- **`procMacro.server` is insurance, not the answer, and nothing tests the day it
  becomes the answer.** Today the built-in server gives byte-identical
  expansions, because the fork is 1.95.0-nightly and the analyzer is 1.95.0. The
  failure this protects against needs two toolchains far enough apart to break the
  bridge, and this machine has no such pair. The setting is proven *live* — a
  bogus path turns the server's health to a warning and every expansion to
  "Expansion had errors" — which is as far as it can be taken here.
- **The esp recipe pins two versions that have to move together**, the image tag
  and the release toolchain, and nothing checks that they agree. A mismatch does
  not fail loudly: everything answers except macro expansion. The Dockerfile says
  so at the pin.
- **The pin is still read once per project**, as 0462 left it, so editing
  `rust-toolchain.toml` or `.abydos/tools.json` while the project is open does not
  change the strip until the project is opened again.

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
- [x] Drive the corrected notice against the real project, with the pin in place
- [x] Write down here what was ruled out on the way
- [x] `spec/tool-images.md` and `spec/language-servers.md` say what the project
      now does
