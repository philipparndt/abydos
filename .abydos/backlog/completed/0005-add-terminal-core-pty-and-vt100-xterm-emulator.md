# Add terminal core: PTY and VT100/xterm emulator

`b11ac91e7` · 2026-07-30

The foundation for terminal integration and, deliberately, for agent sessions.

PseudoTerminal wraps forkpty. A real PTY rather than pipes because interactive
tools only enable colour and full-screen UI when isatty is true, a PTY carries a
window size so programs reflow on resize, and job control works so ^C reaches
the process. It also spawns the login shell with -l, since without it Homebrew
tools are missing from PATH.

Crucially the PTY belongs to ideai, not to any view. That is what will let an
agent session be shown, hidden and shown again — or handed to a terminal view
for the user to take over — while the process keeps running.

TerminalEmulator is UI-free: it consumes bytes and maintains a TerminalScreen,
so escape sequences, wide characters, scroll regions and the alternate screen
are all testable by feeding byte strings and reading the grid back. Covers
cursor movement, erase/insert/delete, SGR including 256-colour and true colour,
scroll regions, the alternate screen, OSC titles, device status replies, and
UTF-8 split across reads.

Two details worth noting: wrapping is deferred until the character after the
right margin actually arrives, otherwise writing exactly `columns` characters
wraps a line early; and growing the window pulls lines back out of scrollback
rather than padding with blanks.

PTY callbacks take an injectable queue — defaulting to main for the app — so
the integration tests do not depend on a running main run loop. That suite is
serialized because forkpty forks a multithreaded process.

95 tests.
