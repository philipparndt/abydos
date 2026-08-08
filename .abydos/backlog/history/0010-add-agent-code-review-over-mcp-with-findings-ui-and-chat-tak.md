# Add agent code review over MCP, with findings UI and chat takeover

`7d23396ea` · 2026-07-30

⇧⌘R reviews the branch. The agent runs in a PTY the window owns and reports
through a per-session MCP server, so findings arrive as typed data — file, line,
severity, title, detail — rather than as text scraped out of a rendered TUI.
They appear incrementally as the agent works, and clicking one opens the file at
that line.

The same session is one click away behind the Chat toggle. Because the PTY
belongs to ideai rather than to a view, switching to the chat is a view change
against a process that never stopped — which is what "jump in and take over"
means here.

Server details that matter: transport is Streamable HTTP over loopback, because
ideai is a running app the agent must call into, and the stdio transport inverts
that relationship. Loopback alone is not access control, so every request must
carry a per-session bearer token. The session is launched with
--strict-mcp-config so the user's own MCP servers stay out of it, and only the
reporting tools are pre-allowed, so the review is not interrupted by a
permission prompt for the thing it was asked to do.

Ingestion is deliberately tolerant: a model that mislabels a severity or omits a
line number should not cost the user the rest of the review.

122 tests.
