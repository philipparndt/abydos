# Detect file types by content, and let the status bar override it

`f40441669` · 2026-07-31

An unknown extension is not evidence that a file is unstructured, but
detection stopped at the extension table and gave up. Package.resolved
is JSON; a .lock file usually is not plain text either. Detection now
falls through to sniffing the first kilobyte for a shebang, a JSON
object or array, an XML or HTML preamble, or a YAML document marker.

Each rule needs a marker that prose or another language would not begin
with — a bare brace opens a C block and a shell function body just as
often as a JSON object, so it takes a quoted key or an immediate close
to count.

Sniffing is still a guess, and the file that defeats it is exactly the
one worth reading with colour, so the guess is now correctable: the
language in the status bar is a control, and picking from it re-parses
the document under the chosen grammar.
