# Abydos 0.24.0

## A .scad is checked and completed by opensolve-scad-lsp

opensolve-scad-lsp, the language server of opensolve-scad, is now the first
choice for OpenSCAD. It runs the file, so a `.scad` is marked with what
rendering it would say — an unknown variable, a wrong argument, an echo, a
failed assert — where each happened. It completes the names of what the file
includes and uses, BOSL2's too, and has signature help. openscad-lsp stays as
the second choice, picked the same way as any other language's alternative.

## A .scad preview is rendered by opensolve-scad, with its colours

The model preview renders a `.scad` with opensolve-scad in one run, rather than
OpenSCAD run once per colour. It is faster, an import of a file beside the
model now comes through, and a coloured cutter in a `difference()` no longer
shows. "Open in OpenSCAD" still opens OpenSCAD.

## A binary file without NUL bytes no longer opens as text

A raw image dump such as an opaque `.rgba` passed the binary test and opened as
one line many megabytes long, which made the window crawl while it was selected.
A file whose head is a tenth or more control characters now gets the binary
notice and its hex editor, as a file with a NUL byte always did.
