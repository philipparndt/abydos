# A completion that says where the caret goes is not text to paste

`938ad14e7` · 2026-08-06

`unio` and Tab put `union() $0` into an OpenSCAD file. The server had said
what it meant — `"insertText": "union() $0", "insertTextFormat": 2` — and the
format was read past: a snippet went in as literal text, which is a syntax
error somebody has to notice and delete.

Snippets are expanded now. `$0` is where the caret lands, `${1:default}`
leaves text to type over, `${1|a,b|}` takes the first, and `\$` is a dollar —
which matters for shell completions, where eating one would rewrite the
command. Anything that is not a snippet is inserted as it was, with the caret
at the end, exactly as before.

Tab stops beyond the caret are left as their default text rather than made
navigable: jumping between them means holding ranges through later edits,
which is a feature and not this fix.

Checked against openscad-lsp itself, both what it sends and what ends up in
the file: `union() ` with the caret between the braces to come, and no `$0`.
