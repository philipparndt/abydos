# Abydos 0.23.11

## A binary file without NUL bytes no longer opens as text

A raw image dump such as an opaque `.rgba` passed the binary test and opened as
one line many megabytes long, which made the window crawl while it was selected.
A file whose head is a tenth or more control characters now gets the binary
notice and its hex editor, as a file with a NUL byte always did.
