## Context

The settings window and the settings tab in the editor are the same
`SettingsPage`: a sidebar listing the sections — Appearance, Terminal, Editor,
Saving, Navigator, Git, Agent, Trust, System, Tools and its children — and a
form on the right showing the rows of the *selected* section, rebuilt from
`SettingsPaneController.Row` values each time the selection changes. Rows carry
a title, an optional sentence of help and a control; groups nest rows in a
card. The proposal called it one long page, which is what it replaced; what it
is now is a list of pages, and finding a row means knowing which page it is on.

The driven verbs already read this shape: `--dump-settings <page>` prints a
page's rows through `SettingsPaneController.describe`, and
`SettingsSections.says` finds a row by page and title.

## Decisions

**A field in the sidebar, above the sections.** Where every settings window
on the machine puts it, the system's included. Typing into it does two things
at once: the sidebar keeps only the sections with a match, and the form stops
showing the selected page and shows the matching rows of *every* matching
section, each under its section's heading, in the sidebar's order. Clearing
the field puts the sidebar and the selected page back exactly as they were.

*Ruled out: filtering only the sidebar.* The sidebar names pages, and "ghostty"
is not the name of a page; a filter that lit up "Terminal" and left the reader
to scroll the Terminal page for the word has done half the job.

*Ruled out: filtering the selected page in place.* A row on another page is the
case people search for. Filtering within the page somebody happens to be on
finds nothing and looks broken.

**Title and help both match, every word, anywhere, case-insensitively.** The
sentence under a control is where the words people search with are — "Engine"
is found by "ghostty" only through its help. "tmux status" finds the row about
tmux's status bar whether "status" is in the title and "tmux" in the help or
the other way round. Substring rather than prefix: "engine" should match
"Terminal engine". A group is kept when its title matches or any row inside it
does; a group kept for its title keeps all its rows, since they are what the
title names.

*Ruled out: fuzzy matching.* Right for a command palette with hundreds of
verbs; over a few dozen rows it finds rows people did not mean and cannot be
explained in a sentence.

**The words are matched in the kit, the rows are walked in the app.** There is
no test target for the window layer, and `Row` lives there. So the part with
decisions in it — what a query is split into, what a title and help have to
contain — is a small type in `AbydosKit` with tests, and the walk over rows and
groups in `SettingsPage` is a few lines that call it and are exercised by the
driven verb.

**Rebuilt, as the page already is.** `show(section:)` tears the form down and
builds the selected page's rows each time; the results view does the same with
several sections' rows. Controls are made from the row's own closures either
way, so a value changed in the results view is the same change as on its page.

**A driven verb.** `--settings-filter <text>` types into the field once the
settings page is up and prints the sections and row titles left, so "ghostty
finds the engine row" is a line a test can read.

**⌘F focuses the field.** Find is what the key means in a window with a list
in it, and the page is in the responder chain of everything it holds.

## Risks / Trade-offs

**A long results page** → "e" matches nearly everything. Accepted: the field
is a filter, and a filter for one letter is the whole list; the reader types
another letter.

**Rows that read differently out of context** → a row called "Enabled" under
Tools ▸ Rust means little on a results page. The section heading over each
group of results is what carries the context, and it is always shown.

## What the driven runs showed, 2026-09-09

- "ghostty": two rows, on two pages — Appearance ▸ Terminal colours, whose
  help mentions Ghostty's palette, and Terminal ▸ Emulate with libghostty-vt.
  The first is the help match the design argued for; the second is the row the
  proposal named.
- "tmux status": three rows. Terminal ▸ Hide tmux's own status bar, which is
  the one meant; the libghostty row and Agent ▸ Let Claude Code say what it is
  doing, both because their help mentions tmux and a status line. Two words
  narrow; they do not pinpoint, and that is the filter's honest answer.
- "zebra": no sections in the sidebar and the one line saying nothing matched.

The page file passed the thousand-line aim with the filter in it, so the
sidebar table and the flipped container moved to a file of their own.

## Release note

> **Settings can be filtered.** A field at the top of the settings sidebar
> narrows the list to the sections with a match and shows the matching rows of
> all of them together, each under its section's name. It matches the help
> under a control as well as its title, so "ghostty" finds the terminal engine
> and "tmux status" finds the status-bar switch. ⌘F puts the cursor in it.

## Open Questions

None left.
