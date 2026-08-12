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
the whole choice turned on. AppKit forgives a modifier the mask does not ask for
when that modifier is what produces the character — so keeping the literal `/` is
not "reachable in theory", it is reachable, and that was the thing the item said to
measure rather than assume.

Option is forgiven on the same terms as shift: ⌥⌘5 reaches an item declaring `[`.
**This was measured wrong twice before it was measured right**, and the first
answer — that option is *not* forgiven — was written into this item and into two
code comments before the third measurement took them back out. See below for what
made the difference.

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

## Which of the three, and what the others would have cost

**`allowsAutomaticKeyEquivalentLocalization = false`, on this one item.** One line
in `AppDelegate`. The menu now reads ⌘/ and ⌘⇧7 reaches it, both measured, and the
real menu bar was handed that press and the file changed under it.

The item warned this one "fixes nothing and looks like it should" if AppKit will
not match a shifted character against a command-only mask. **It does match** — a
modifier needed to type the character is forgiven — which is why this is the answer
and why it had to be measured first.

- **Declaring it twice** — `/` with ⌘ and `7` with ⌘⇧, the second hidden — is
  unnecessary once the leniency is known: the second declaration would match the
  same press the first one already matches. It would also put ⇧7 in the menu, which
  is only where `/` is on *this* layout; a French AZERTY types `/` with ⇧: and the
  hidden alternate would be a shortcut for a character nobody asked for.
- **Answering it in `keyDown`** was the most robust and the most expensive. Every
  editor command in this app is routed by the menu, and the command palette is
  *built from the menu* (`MenuCommands.all` walks the menu bar) — so a keyDown-only
  ⌘/ would vanish from the palette, from the Edit menu's own listing of what it can
  do, and from anywhere somebody looks a shortcut up. It also duplicates the
  matching AppKit already does, on a code path that runs per keystroke.

## Is this a code fix or a menu-honesty fix

**A code fix, and the menu was honest all along.** It said ⌘ß and ⌘ß worked; the
mismatch was between the menu and every editor on earth, including the sentence the
person who asked for the feature wrote. ⌘ß is not a shortcut a German user would
try for commenting — nothing documents it, no other editor has it, and it is a
letter key that means nothing — so what the relocation cost was the whole feature
rather than one keystroke. And it is not honest *for free* either: 0475's own note
called ⌘ß "the feature doing its job", and it took a morning's report to find out
that the job it did was hiding a command.

The menu now reads what somebody was told, and the press is the one that makes a
`/`. Both halves right, rather than one.

## The other shortcuts on this layout

`--menu-keys` swept all 76 shortcuts in the menu bar. **Every one of them lands
where the menu says it does**, before this change as well as after. There is no
second instance of this bug: for every other shortcut, what the system did was
either invisible or an improvement.

- `[` and `]` — Back and Forward — are typed with ⌥5 and ⌥6 on a German keyboard.
  The system moved them to **⌘Ö** and **⌘Ä**, the physical keys where `[` and `]`
  sit on a US keyboard, and both answer. Next Tab and Previous Tab likewise, at ⇧⌘Ä
  and ⇧⌘Ö.
- `\` — the splits — is ⌥⇧7 here, and moved to **⌘#** and **⇧⌘#**: again the same
  physical key.
- `=`, the second Zoom In, moved to **⌘\*** for the same reason.
- `,` `+` `-` and every letter are unshifted on this layout and were left alone.
- The relocations are consistent, and this is the part worth knowing: the system
  moves a shortcut to *the key in the same place on the keyboard*. ⌘Ö for Back is a
  better answer than anything this app could have written down, and it is why
  turning the localisation off item by item is a judgement rather than a policy.

**What turning it off across the app would actually cost**, since that was the
obvious generalisation and had to be measured rather than assumed:

- Back becomes ⌥⌘5 and Forward ⌥⌘6 — reachable, but a modifier worse than ⌘Ö, on a
  key nothing is printed on.
- **Split Down becomes unpressable.** `\` is ⌥⇧7, so the forgiven shift makes `⌘\`
  and `⇧⌘\` the same press; Split Right answers it and Split Down never gets asked.
  Two commands, one keystroke, and no way to tell from either declaration.

`/` has neither problem — one extra shift, and it collides with nothing — which is
what makes it the one item worth taking out of the system's hands.

Two things the sweep turned up that are not about German at all:

- **The palette wrote ⌘ß as ⌘SS.** `ShortcutText.name(of:)` upper-cased any
  single-character key, and `ß`.uppercased() is two letters. Fixed here, with a
  test, because a shortcut written down wrong is this item's own bug in a smaller
  size — and a relocated key is exactly how a `ß` gets into a key equivalent.
- **Reading the keyboard layout aborted the process when two threads asked at
  once.** Text Input Services calls `abort()` inside `isValidateInputSourceRef`;
  four new tests that each passed alone took the whole suite down with signal 6 and
  no message pointing anywhere. `KeyboardLayout.current()` holds a lock, and
  `theLayoutCanBeReadFromSeveralThreadsAtOnce` is the guard.

### Ruled out

- **Turning the localisation off across the whole menu bar**, which was the obvious
  generalisation. Measured rather than feared, and the measurement was not the one
  expected: the other shortcuts stay reachable, they just get worse — except Split
  Down, which becomes unpressable because `⌘\` and `⇧⌘\` collapse onto one press.
- **"An extra option is not forgiven"**, which is what two earlier measurements
  said and which was written into this item and two code comments before the third
  took it back out. Both earlier attempts assembled the `NSEvent` by hand; ⌥⌘5 does
  reach an item declaring `[`. The lesson is not about AppKit: **a measurement made
  with an instrument that has been wrong once should be repeated with a better one
  before it is written down as a finding**, and this one was written down twice.
- **Declaring the shortcut twice**, and **answering it in `keyDown`**: both above,
  both with what they would have cost.
- **Concluding that ⌘ß is correct and the fix is in the documentation.** The item
  offered this and it was seriously considered — the menu really was telling the
  truth. It fails on what a shortcut is *for*: ⌘/ is muscle memory shared by Xcode,
  VS Code and IDEA, and a German user does not learn a different comment key for
  this one editor. Documenting ⌘ß would have been documenting a shortcut nobody
  would use.
- **Pressing the key through the window server.** Still impossible, still for
  0475's reason: a menu key equivalent is matched against the *key window's*
  responder chain and a binary driven from a terminal never becomes key. What is
  new is that this no longer matters: the press can be handed to
  `NSApp.mainMenu.performKeyEquivalent(with:)` directly, and everything but the
  window server's delivery is then exercised — the item matched, the action ran, the
  file changed. `COMMENTKEY the real menu answered it and the text changed`.
- **A test in the suite for any of this.** The menu is built in `AbydosApp` and the
  suite only reaches `AbydosKit`, so the claim "every shortcut is reachable" cannot
  live there. `KeyboardLayout` and `ShortcutText` are tested; the sweep is a driver,
  which is the same shape as every other thing in this app that needs a window.
- **Switching the keyboard layout.** Not done and not needed: the machine was
  already German, which is the only layout this shows on, and everything above was
  watched on it. Nothing about the user's input sources was changed.

## Watched, on the German layout it was reported on

A throwaway copy of a Swift file in a throwaway project, never anybody's checkout,
under a throwaway bundle identifier and a throwaway defaults domain.

- `--comment-key` before: `key=ß`, one press reaches it — ⌘ß — and ⌘⇧7 reaches
  nothing.
- `--comment-key` after: `key=/`, and `on “German” the menu says ⌘/, and it is
  pressed as ⇧⌘7 … or ⌘/ (keypad)`, followed by a line per press saying the real
  menu answered it and the text changed. The file on disk came back commented.
- `--menu-keys` after: all 76 shortcuts, each pressed as what the menu shows.

### The slash on the numeric keypad, which was asked for and which also works

`⌘/` on the keypad reaches Toggle Comment, and **that is new too** — before this
change the item's key was ß, so the keypad's slash was as dead as the main block's.
Every press the sweep finds is now sent at the real menu bar rather than only the
first, because ⇧⌘7 and the keypad's ⌘/ are different keys and a check that stopped
at the first would have said nothing about the second: `⌘/ (keypad) at the real
menu: answered it and the text changed`.

Two things about the keypad had to be measured rather than assumed, because a
keypad press is not a main-block press with a different key code:

- **It carries `numericPad` in its modifier flags**, so the sweep sets that flag for
  keypad key codes. It changes no answer — AppKit tolerates it — but a report about
  the keypad that left it out would be a report about a press nobody makes.
- **AppKit does *not* tolerate the neighbouring `function` flag**: the same event
  with `maskSecondaryFn` set reaches nothing. It is tolerated for a *function-key*
  equivalent — ⇧F6 and ⌥⌘→ both still match with it on — so the rule is per key
  rather than blanket. Which is incidentally the proof that a real keypad press does
  not carry it: if it did, ⌘ with a keypad key would work in no application at all.

## Estimate

2026-08-12 08:17 — about twenty minutes left, for the suite and the warnings

## Steps

- [x] Measure which press fires it today, with `commentKeyReportForTesting`
- [x] An instrument that can answer it: `--menu-keys`, a shadow of the menu bar
      swept by every press a keyboard can make. Added because the question is
      *which key*, and nothing in the app or the suite could see the key
- [x] Decide between the three, and say what the other two would have cost
- [x] ⌘/ as asked for, or a menu that honestly reads what works — and say which
      this is
- [x] Check the app's other shortcuts on this layout, and say what you found
- [x] Watch it on a German layout, which is the only place this shows
- [x] The slash on the numeric keypad works as well, and every press the sweep
      finds is sent at the real menu rather than only the first. Added because it
      was asked for, and because the keypad is a different key with a modifier
      flag of its own
- [x] The palette writes ⌘ß as ⌘SS. Found by the instrument, and it is the same
      bug as this item — a shortcut written down wrong — so it is fixed here
- [x] Reading the keyboard layout aborts the process when two threads ask at once.
      Added because four new tests took the whole suite down with signal 6, and a
      value that cannot be read twice at once is not one to hand anybody
- [x] Write down here what was ruled out on the way
- [x] `spec/editor.md` says what the project now does: ⌘/ is ⌘/ on every keyboard,
      and every other shortcut is still the system's to move
