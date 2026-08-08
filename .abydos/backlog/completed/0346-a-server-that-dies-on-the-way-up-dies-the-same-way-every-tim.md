# A server that dies on the way up dies the same way every time

`b11d4cb36` · 2026-08-07

"rust-analyzer did not answer" arrived every twenty or forty seconds, for
ever. The rule that produced it is a good one — a server that crashed is
started again rather than silently doing nothing — but it does not hold for a
server that has never worked. Here `~/.cargo/bin/rust-analyzer` is a rustup
shim with nothing behind it: it exits in one second with "Unknown binary
'rust-analyzer' in official toolchain", every single time. So every request
started it, every start failed, and every failure was said out loud.

A handshake that fails now stops that project's server for good, and opening
the project again is what asks for another go — which is also when somebody
has had a chance to install the thing.

And the toast says what the server said. "The language server is not running"
is what the client knows and the one thing nobody can act on; the line the
server wrote on its way out names the problem and, in this case, the fix.

Measured against the shim that caused it: one start in seventy seconds where
there had been three.
