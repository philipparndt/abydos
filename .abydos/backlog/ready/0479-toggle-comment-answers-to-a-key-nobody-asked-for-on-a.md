# 479. Toggle Comment answers to a key nobody asked for on a German keyboard

0475 shipped ⌘/ and it was reported not working the next morning. **It is not
missing and the app is not stale** — the binary running was installed at 07:12 and
started at 07:16, well after that merge, and it carries the symbols.

    defaults read com.apple.HIToolbox … → "KeyboardLayout Name" = German;

`AppDelegate.swift:2017` builds the item with `keyEquivalent: "/"` and
`keyEquivalentModifierMask = [.command]`. On a German layout `/` is **Shift+7**, and
macOS's automatic key-equivalent localisation moves the shortcut to a key that needs
no shift — **the menu shows ⌘ß.** So the app is listening for one press and the
person is making another, and 0475's own report flagged this before it landed:

> On a German keyboard the menu shows ⌘ß. AppKit localises key equivalents
> automatically; `/` needs Shift on that layout, so it moves the shortcut to a key
> that does not. Left alone — the alternative is ⌘⇧7.

Left alone was the wrong call, and this item is the correction. **Whatever the fix,
the first thing to establish is which press works today** — ⌘ß, ⌘⇧7, both or
neither. `commentKeyReportForTesting` in `MainWindowController` already prints the
item, its key, its modifiers and whether the responder chain answers, so the
measurement is cheap. Do it before choosing.

## What the three answers cost

- **`allowsAutomaticKeyEquivalentLocalization = false`** (macOS 12+) keeps the
  literal `/`. But then the shortcut is only reachable as ⌘⇧7 on this layout, and
  whether AppKit matches a shifted character against a `[.command]`-only mask is the
  thing to *measure* rather than reason about — if it does not, this fixes nothing
  and looks like it should.
- **Declare it twice**: `/` with `[.command]` and `7` with `[.command, .shift]`, the
  second hidden as an alternate so the menu still reads one way. Reliable, and it
  puts layout knowledge in the menu, where it will be wrong for the next layout
  somebody uses.
- **Answer it in `keyDown`** on the code view, matching the character the layout
  actually produces rather than a declared equivalent. Most robust across layouts
  and the one that stops being about German — but it takes the shortcut out of the
  menu's own routing, which is where every other editor command lives, and a
  shortcut absent from the menu is a shortcut nobody discovers.

**And say what the menu should read.** A German user pressing what the menu shows is
not confused; a German user told ⌘/ and shown ⌘ß is. If the localisation is kept,
the item is *right* and the report was about a mismatch between the release note and
the menu — which is a documentation fix, not a code one. Decide which of those two
this is, because it changes what "fixed" means.

## Wider than one item

Every other shortcut in this app is declared the same way, so if automatic
localisation is moving this one it is moving others: `⌘,`, `⌘⇧P`, `⌘⌥→`. Check a
handful and say whether they land where the menu says. **A shortcut that works but
is not the one written down is the same bug wearing different clothes**, and this
machine is the only one in the project that would ever show it.

## Steps

- [ ] Measure which press fires it today, with `commentKeyReportForTesting`
- [ ] Decide between the three, and say what the other two would have cost
- [ ] ⌘/ as asked for, or a menu that honestly reads what works — and say which
      this is
- [ ] Check the app's other shortcuts on this layout, and say what you found
- [ ] Watch it on a German layout, which is the only place this shows
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does, if anything user-facing
      changed
