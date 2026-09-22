# Abydos 0.23.1

## A page in the HTML preview can be allowed the network

The preview refuses every remote reference, and now says so with a *Load*
button beside it. Pressing it lets that page fetch — the stylesheet at a CDN,
the font it names, the picture on somebody's server — and the line changes to
say the page is being fetched, with *Block* to take it back.

The offer is about the page rather than the address in the line, because a font
stylesheet names files on a second host and allowing one address alone would
leave the page unstyled.

An allow is remembered for that one file, outside the project, so a repository
never arrives with permission to fetch already granted and nothing appears in
`git status`. A file that is renamed asks again. Allowing a page is not
trusting a project: an allowed page in an untrusted project fetches its
stylesheet and still runs no script. A driven run fetches nothing whatever is
remembered, and the line says that is why.
