## Context

The HTML preview blocks every load that is not this app's own scheme, with a
`WKContentRuleList` compiled once for the process and added to each pane's web
view. A relative reference reaches `HtmlScheme` and is served from beside the
file; an absolute one never starts. What the document asked for is counted from
its own tags, because a content rule list drops a request silently, and the
pane says the count and the first address at its foot.

That is the state this change touches. Nothing about the scheme handler, the
containment rule or the counting changes; what changes is that the block can be
lifted for one document, by the person reading it, and that the pane remembers.

`ProjectTrust` is the model for the remembering, and it is worth naming what
this borrows: a store in Application Support rather than in the project, a
resolved path as the key, and a `persists` flag that a driven run turns off so a
capture never writes into somebody's real list.

## Goals / Non-Goals

**Goals:**

- One press turns a refused page into a fetched one, and the page looks the way
  it looks in a browser.
- The decision survives closing the file and reopening it.
- What the pane is doing is legible at all times: refusing and saying what, or
  fetching and saying so.
- Taking it back is as cheap as granting it.

**Non-Goals:**

- **No allow-listing of hosts.** Not "always allow fonts.googleapis.com", and
  not a list of hosts in the settings. The unit is the document, because that is
  the thing somebody is looking at and can judge. A host list is a policy, and a
  policy is a thing people stop reading.
- **No per-request prompt.** A page has dozens of references; a dialog per
  request is a page nobody previews twice.
- **Not a browser.** An allowed page fetches its subresources. It still cannot
  navigate the pane, its links still open elsewhere, and its scripts still need
  a trusted project.

## Decisions

### The unit is the document, not the address

The line names one address because naming twelve would be a paragraph, but the
button cannot mean that address alone. A Google Fonts stylesheet names font
files on another host; a CDN script fetches its own chunks. Allowing the first
and refusing the second leaves a page that is still broken and a line that now
undercounts, which is worse than refusing everything.

**Ruled out:** allowing the named address only, and counting again after the
reload to offer the next one. It turns one press into four, and each press is
the same decision made again with less information than the first.

### Lifting the block is removing the rule list, not compiling a permissive one

`WKUserContentController.removeAllContentRuleLists()` on that pane's controller,
then reload. The web view is the pane's own and nothing else shares it, so this
cannot leak to another document.

**Ruled out:** a second compiled list that blocks nothing. It is the same effect
bought with a second thing to keep correct, and a list that "blocks nothing" is
one typo away from a list that blocks nothing *anywhere*.

### The allow is kept outside the project

`AllowedPages` writes a JSON file in this application's support directory,
keyed by the file's resolved path — `ProjectTrust`'s arrangement, for
`project-trust`'s reason, stated there as "trust is remembered per folder,
outside the project".

**Ruled out:** keeping it in the project, under `.abydos/`. An allow is a
statement about this machine reaching that server; committed, it would be
inherited by everyone who clones the repository, and a file that arrives with
permission to fetch already granted is exactly the shape of thing this pane's
default exists to prevent. It would also put a line in `git status` for reading
a file, which the previews spec forbids on its own terms.

**Ruled out:** a settings toggle for the whole application. The pane would stop
being able to say anything useful, since every page would fetch and the line
would never appear. The request was a button on a document, and the unit stays
the document.

**A path is a weak key, and that is accepted.** A file that is renamed or moved
loses its allow and asks again, which is the safe direction to fail in. Nothing
is stored about the file's contents, so a document that changes completely under
a path it kept is still allowed — the same trade `ProjectTrust` makes for a
folder whose contents change.

### Trust and allowing are separate rules

Fetching a stylesheet does not run the project's code. `project-trust` is about
what starts; this is about what is reached. So the button is offered in an
untrusted project, and an allowed page there fetches its stylesheet and still
does not run its scripts. The two lines sit beside each other in the caption
when both apply, which is the one place somebody sees the difference stated.

**Ruled out:** requiring trust before allowing. It reads tidy and says the wrong
thing — that fetching a font is the same act as running a stranger's JavaScript
— and it would put two gestures in front of somebody looking at their own file.

### A driven run does not fetch, whatever is remembered

`LinkOpener` prints what it would have opened rather than opening a browser on a
driven run, because a capture must not act on the world. The same argument
applies harder here: a suite or a screenshot run that fetched Google Fonts would
be a test that fails on an aeroplane and a picture that differs by network.

So a driven run keeps the rule list on for every document, and the pane says
that is why, rather than silently rendering a page somebody allowed as though
the allow had not been read.

### The caption becomes a row

The line already truncates in a narrow pane, which is why it truncates from the
tail. A button at its trailing edge takes more room, so the caption becomes a
horizontal stack: the sentence, then the button, pinned right and sized to its
title. The sentence keeps whatever is left.

**Ruled out:** a button that floats over the page, and a bar above it. Both put
a control where the document is, and the whole of this pane's chrome is one line
at the foot.

## Risks / Trade-offs

- **Somebody allows a page that carries a tracking pixel** → The pane says how
  many references a page has and names the first before anything is pressed, and
  the allow is one document wide rather than a host or a setting. Taking it back
  is one press.
- **An allowed page is slow, or hangs on a server that never answers** → It is a
  web view; the page's own loading is the page's problem, and the pane is still
  closed by leaving the mode. No deadline is proposed, because a subresource
  timing out is a browser's ordinary behaviour rather than a hang this app has
  to detect.
- **The remembered list grows** → One line per file somebody pressed a button
  on. `ProjectTrust`'s list has the same shape and the same non-problem.
- **A moved file silently asks again** → Stated above as the safe direction.
  Worth a sentence in the release notes rather than a mechanism.

## Settled while building

- **An allowed page does not show the count.** Photographed both states in a
  580-point pane: the refused line runs to the edge and truncates, and the
  allowed one — "This page is being fetched from the network." — leaves room
  for the button beside it. Adding "of twelve references" to the second would
  push it back to truncating for a number nobody acts on. The count is what
  tells somebody what they are agreeing to, and it is on screen when that is
  the question being asked.

## Found while building

- **The line was set and drawn nowhere.** The caption became a stack, and its
  height was taken from `fittingSize` when the caption changed — which is
  before the row has laid out, so it measured zero. The report said the
  sentence was there and the screenshot showed the page filling the pane. The
  height constraint is gone: an `NSStackView` closes up around hidden arranged
  views on its own, which is the note `DiagramPaneView` already carried. Found
  by putting the row's height into the pane's own report, which is where it
  stays.
- **A path resolves only for a file that exists.** `resolvingSymlinksInPath`
  stats the path, so `/tmp/x` and `/private/tmp/x` are two keys when nothing is
  at them and one key when something is. It costs nothing here — the pane asks
  only about the document it is showing — and it is the same reason a moved
  file loses its allow.
