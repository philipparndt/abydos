## Context

See proposal.md — Why. What shapes the approach is one property:
`intrinsicContentSize` is what a view-based `NSToolbarItem` offers the toolbar,
the toolbar treats it as a fixed demand, and there is no equivalent of "I could
be narrower if you needed". So the only way to stop an item being hidden is for
it not to ask for more than there is.

## Goals / Non-Goals

**Goals:**

- The project name and branch are visible on a repository with a long name and a
  long branch.
- A name and branch that already fit are drawn exactly as they were.

**Non-Goals:**

- Rearranging the toolbar, or changing which item gives way first.
- A capsule that tracks the window width. It would be better — see the risk
  below — and it needs the item to be re-measured on every resize, which is a
  larger change than the fault warrants.

## Decisions

### A maximum width, with the text shortened to fit it

The alternative was to raise the item's `visibilityPriority` so the toolbar drops
something else — the run-configuration control, most likely. **Ruled out for
now**, though it is the more complete answer: the file records a deliberate
decision that the capsule is the first thing to go because the switcher is in the
menu bar as well, and overriding that is a design change rather than a fix. The
fault is narrower than that decision: the capsule was hidden at a width where a
shortened branch would have fitted.

### Shortened from the middle, and the branch before the name

Tail truncation would leave `fix/dev-user-servi…`, which is the half a reader
could have guessed. The middle keeps `fix/` and `memory-limit`, which between
them identify the branch. The name is shortened only after the branch has no room
left, because the name is the project's identity and is almost always the shorter
of the two.

### The constant, and how it was chosen

`scaled(360)`, against a `minimumWidth` of `scaled(300)`. Chosen by photograph
rather than by arithmetic: in the driven capture, `scaled(400)` was still hidden
and `scaled(360)` was not. It is a constant fitted to one observed toolbar width,
which is the weakest part of this change and is written down as such below.

## Risks / Trade-offs

**The constant is fitted to one window width** → A window narrow enough leaves
less than `360` for the capsule, and it will be hidden again. `--window-size` did
not change the size of the driven capture, so the width at which that happens was
not measured and is not known. The complete answer is either the priority change
ruled out above, or a width that tracks the window; this change buys back the
reported case and does not claim more.

**A shortened branch is ambiguous between two similar branches** →
`fix/dev-us…ory-limit` and `fix/dev-us…ory-limits` read alike. The full name is
one hover away in the tooltip and one glance away in the terminal's prompt, and a
name shortened in the middle is still a better answer than no capsule at all.

## Open Questions

- Whether the capsule should outrank the run-configuration control when a window
  really is too narrow for both. It is a question about which of the two a person
  would rather lose, and the answer belongs to whoever uses the app rather than to
  this change.
