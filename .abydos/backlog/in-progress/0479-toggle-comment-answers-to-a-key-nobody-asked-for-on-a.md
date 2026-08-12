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

## What was measured

The layout was already German and was **not changed for any of this** — everything
below was watched on the keyboard the report came from, which is the only place it
shows.

**⌘ß fires it. Nothing to do with `/` does.** The item reports `key=ß` with a
command-only mask and a responder chain that answers, and the sweep finds exactly
one press that reaches it: ⌘ß. ⌘⇧7 — the way a `/` is typed on this keyboard —
matches nothing at all. So the person who asked for ⌘/ pressed the only thing ⌘/
can mean here and the app was listening on a key they had no reason to try.

**⌘⇧7 does reach an item declaring `/` with ⌘ alone**, which is the measurement
the whole choice turned on. AppKit forgives a shift the mask does not ask for when
the shift is what produces the character — so keeping the literal `/` is not
"reachable in theory", it is reachable, and that was the thing the item said to
measure rather than assume.

An extra **option** is not forgiven, which is the other half and the reason the
localisation must stay on everywhere else: `[`, `]`, `\` and `=` all need ⌥ on a
German keyboard, and no press whatsoever reaches an item declaring them literally.

### How it was measured, since pressing the key is still impossible

0475 established that a menu key equivalent is matched against the *key window's*
responder chain and that a binary driven from a terminal never becomes key. That
is unchanged. What is new is that the *matching* can be measured without any of it:
every item is copied into a menu of its own whose one item points at a harmless
object, and the copy is asked `performKeyEquivalent(with:)` for every key on the
keyboard by every modifier combination. Same matcher, same key equivalents, and
nothing performs a real action — `--menu-keys` prints it for the whole menu bar and
`--comment-key` now prints it for ⌘/.

Two attempts at this were wrong in ways worth writing down, because both looked
right:

- **One shadow menu holding every item.** A menu answers a key with its *first*
  matching item and stops, so ⇧⌘N was reported unreachable because ⌘N sat above it.
  Half the report was wrong in the direction that reads as a finding, which is the
  worst direction for a measurement to be wrong in. One shadow menu per item.
- **Assembling the `NSEvent` by hand.** The two character fields of a real event do
  not agree the way the documentation reads: with command held, `characters` drops
  the shift (`y`) while `charactersIgnoringModifiers` keeps it (`Y`). And key code 6
  is `z` on a US keyboard and **`y` on this one**, so a table of assumed characters
  was not even on the right keys — the sweep claimed ⇧⌘Z reached Undo rather than
  Redo. Now the events come from `CGEvent(keyboardEventSource:virtualKey:)` wrapped
  in `NSEvent(cgEvent:)`, so the *system* fills the characters in from the layout
  and the flags. An event the system built cannot be wrong about the keyboard it
  was built on.

## Estimate

2026-08-12 07:38 — about two hours left

## Steps

- [x] Measure which press fires it today, with `commentKeyReportForTesting`
- [x] An instrument that can answer it: `--menu-keys`, a shadow of the menu bar
      swept by every press a keyboard can make. Added because the question is
      *which key*, and nothing in the app or the suite could see the key
- [ ] Decide between the three, and say what the other two would have cost
- [ ] ⌘/ as asked for, or a menu that honestly reads what works — and say which
      this is
- [ ] Check the app's other shortcuts on this layout, and say what you found
- [ ] Watch it on a German layout, which is the only place this shows
- [ ] The palette writes ⌘ß as ⌘SS. Found by the instrument, and it is the same
      bug as this item — a shortcut written down wrong — so it is fixed here
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does, if anything user-facing
      changed
