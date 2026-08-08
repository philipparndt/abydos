# Record what the terminal was actually given, when asked

`e42eb080b` · 2026-08-08

`ABYDOS_TERM_LOG=<path>` appends every byte the program produced, and
nothing otherwise. The questions worth asking about a terminal are about
the bytes it was handed, and reconstructing those from the program that
sent them is guesswork: what `script` records is what the program wrote,
not what arrived here after tmux and the line discipline had their turn.

Written for #50 and it earned itself immediately — the stream showed all
six graphics commands arriving intact, which moved the search from "the
picture is not being sent" to "the picture is not being put where it
belongs".
