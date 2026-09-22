## Why

Asked for on 2026-09-22, with a screenshot of the pane's own line under a page
that had lost its typeface: "this is fine — but maybe it would be good to have
a button to allow it".

> 1 remote reference was not loaded — https://fonts.googleapis.com/css2?family=Bricolage+Grotes…

The refusal is right and stays right: a page in a repository is full of CDN
tags and tracking pixels, and a preview that fetched them would make opening a
file a network event. What it costs is the one case where the person looking at
the page *wrote* it and knows exactly what it wants. A site's own index linking
a font is not a tracking pixel, and today there is nothing to do about it but
open a browser — which is the thing the preview exists to save.

So the sentence gains a way to answer it. The pane says what it refused, and
beside that it offers to load it.

**The button cannot honestly be about one address.** `fonts.googleapis.com`
answers with a stylesheet whose `@font-face` rules name files at
`fonts.gstatic.com`, so allowing the address in the line leaves the page still
unstyled and the count still on screen. What can be offered is what somebody
actually means by pressing it: let *this page* reach the network.

There is no originating `.abydos/backlog` item: the backlog is retired and this
comes from a direct request.

## What Changes

- **A refused page offers to load it.** Where the caption says what was not
  loaded, a *Load* button sits at the end of the line. It appears only when
  something was refused.
- **Pressing it lifts the block for that document and reloads.** The content
  rule list comes off that pane's web view, so the stylesheet, the fonts it
  names and anything else the page asks for are fetched as a browser would.
- **The allow is remembered, per file, outside the project.** A page somebody
  reads often stays styled across sessions. It is stored the way trust is —
  keyed by the file's resolved path, in this application's own support
  directory, never in the project — because an allow is a decision about
  somebody's machine and their network, not a property of a repository that
  everyone who clones it inherits.
- **An allowed page says so, and can be taken back.** The line reads that the
  page is being fetched from the network, with a *Block* button that puts the
  rule list back, reloads and forgets the allow.
- **Trust is unchanged and still separate.** Fetching a stylesheet does not run
  the project's code, so the button is offered whether or not the project is
  trusted — and an allowed page in an untrusted project fetches its stylesheet
  and still does not run its scripts. Two different rules about two different
  things, each said in its own words.
- **A driven run never fetches**, even for a file somebody allowed, and says
  that is why. `LinkOpener` already refuses to open a browser on a driven run
  for the same reason: a capture run must not depend on the network or reach
  anybody else's server, and a suite that fetched Google Fonts would go red on
  an aeroplane.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `html-preview`: *Nothing is fetched, and what was refused is said* becomes
  *Nothing is fetched until somebody asks for it* — the refusal is the default
  rather than the whole rule, the pane offers to lift it for one document, and
  what an allowed page does is said in its own line. A new requirement beside
  it covers where an allow is kept and what forgets it.

## Impact

- **AbydosKit**: `Preview/AllowedPages.swift` (new) — the store, in
  `ProjectTrust`'s shape: a JSON file in Application Support, a resolved path
  per entry, and `persists = !DrivenRun.isActive` so a driven run's allow never
  lands in somebody's real list. `Preview/HtmlPage.swift` gains the sentence an
  allowed page says, beside the one it says when references were refused.
- **AbydosApp**: `Editor/HtmlPreviewView.swift` — the button at the end of the
  caption line, removing and restoring the rule list, and the reload each way.
  The caption becomes a row rather than a label, since the line already
  truncates and the button takes room from it.
- **Tests**: `AllowedPagesTests` for the store — remembering, forgetting, not
  persisting on a driven run, and a path that moves. `HtmlPreviewLiveTests`
  gains the two states of the web view: a rule list on, and off after an allow,
  checked by what reaches the scheme handler rather than by fetching anything.
- **Release notes**: 0.23.0 says "Nothing is fetched" without qualification.
  That sentence gets the clause it now needs, in whichever version carries this.
- **No `.abydos/backlog/spec` file is made untrue**: the backlog is retired.
