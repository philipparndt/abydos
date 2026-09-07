## Why

**Becoming the default editor asked the system's question sixteen times.**
`DefaultEditor.makeDefault` called `setDefaultApplication` once per kind the
bundle declares, and macOS confirms each call with a dialog of its own — *Do
you want all "Source Code" documents to open with "Abydos" or to keep using
"Xcode"?* — so agreeing once in Abydos meant answering the Finder sixteen
times in a row. Seen on 2026-09-07: "this dialog has to be confirmed for each
file type".

No originating backlog item: reported directly.

## What Changes

- **The bundle declares `public.text`**, the parent of every text kind it
  already declares, so the family has one root.
- **The roots are claimed first** — with `public.text` declared, that is one
  call and one dialog — and then only the kinds Launch Services still does not
  give this app, which are the ones another application binds by name and
  which are worth a dialog each.
- Nothing about the ask itself changes: it is still asked once in Abydos, can
  still be refused for good, and the settings page still reads back what the
  system believes.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `system-integration`: *Being made the default is asked for once* gains how
  the system's own confirmations are kept few.

## Impact

- `Resources/Info.plist` — `public.text` first in the editor entry's kinds.
- `Sources/AbydosKit/Support/TypeFamilies.swift` — `roots(of:)`, tested.
- `Sources/AbydosApp/DefaultEditor.swift` — the two passes.
