## Context

`setDefaultApplication(at:toOpen:)` is the only call there is, and on the
macOS this app requires the system confirms each one with its own dialog. The
bundle declared sixteen text kinds as an editor, so *Make Abydos the default*
was sixteen dialogs. Launch Services resolves a handler through a kind's
parents when nothing binds the kind directly; seven of the sixteen conform to
none of the others, and all sixteen conform to `public.text`.

## Goals / Non-Goals

**Goals:** as few system dialogs as the system allows; the same result the
sixteen calls gave; the page still reading the truth back.

**Non-Goals:** suppressing the system's dialog, which cannot be done and
should not be; claiming kinds the bundle does not declare.

## Decisions

### `public.text` is declared, so the family has one root

A text editor can say it edits text. Declared first in the entry, it is what
the Finder shows for the whole family, and one call binds it.

*Ruled out:* claiming only the seven roots there already were — seven dialogs
is fewer than sixteen and still not one.

### Two passes: the roots, then what is still not ours

After the roots, `typesThisAppOpens()` asks Launch Services which declared
kinds now resolve to this app, and the second pass calls only for the rest —
a kind another application binds by name, like Xcode with `public.source-code`.
That dialog is a real question and is asked.

*Ruled out:* trusting the roots alone. A kind bound elsewhere by name would
stay elsewhere and the page would say so; the second pass is what makes the
button do what it says.

## Risks / Trade-offs

- [`public.text` covering more than the editor colours] → the bundle offers
  rather than claims (`LSHandlerRank: Alternate`), and the second pass never
  claims anything not declared.
- [Not drivable] → the dialogs are the system's; `TypeFamilies.roots` is
  tested, and the declared kinds' single root is pinned by a test over the
  identifiers the plist names.
