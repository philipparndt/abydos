# Every language the examples use, built for the pod

`018df8661` · 2026-08-02

Zig, Odin, C, C++ and Rust all cross-compile now, and four of the five go
through zig — which is a cross compiler for C and C++ as well as its own
language, and a linker for the rest. Verified by running each one in a
cluster and reading what the pod printed, not by reasoning about it:

    zig     fib(10) = 55
    odin    coldest  loft of kitchen, bedroom, garage, cellar, loft
    c       coldest: garage
    c++     warmest: sensor-5
    rust    warmest: sensor-5

Three things only a real run could have found. zig spells a target
aarch64-linux-musl where cargo spells it aarch64-unknown-linux-musl, and
rejects the other with "UnknownOperatingSystem". Rust and zig each ship
musl's start files and the linker will not take both — "duplicate symbol:
_start" — so rustc is told to leave its own out. And `target/<triple>/debug`
holds directories as well as the binary, which the file manager reports as
executable, so the push tried to open `build/` as a file.

Rust needs its standard library for the target, which only rustup can put
there; when it is missing it says which command to run.

Tests cover the choosing and the commands: which build each kind of project
gets, that a make step beats all of them, that an unrecognised project is
told about rather than guessed at, and that what zig is handed is static,
unoptimised and carries debug information.
