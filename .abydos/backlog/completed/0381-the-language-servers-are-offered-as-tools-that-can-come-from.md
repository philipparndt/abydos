# The language servers are offered as tools that can come from an image

`3ace5220d` · 2026-08-08

Six of them — gopls, rust-analyzer, pyright, typescript-language-server,
clangd, jdtls — which are the tools somebody would otherwise install by
hand, and the reason is never the server: it is the toolchain behind it.
A Go install to get gopls, a Rust one for rust-analyzer, a JDK for jdtls.

None of them lists a known-good image, and that is deliberate. The point
of that list is that somebody has run the thing; listing one nobody has
tried would be exactly the failure the list exists to prevent. So each
offers the installed copy and a custom image, and says precisely what a
custom image has to do.

Which is the same for all six, written once so the six cannot drift: the
server on the entry point, speaking the protocol on standard input and
output, no wrapper printing a banner first — the first thing sent is a
header — the project at /workspace, and everything else it needs inside
the image, because nothing on this machine is visible from in there.

The test asserts the absence as well as the presence: no entry may claim
an image, and every requirement must mention all of it, including the
banner, which is the one that is easy to leave out and turns into a
server that starts and never answers.
