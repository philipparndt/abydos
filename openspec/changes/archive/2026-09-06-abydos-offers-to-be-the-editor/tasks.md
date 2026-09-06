## 1. What the bundle says

- [x] 1.1 `Resources/Info.plist` — the document types, one entry per system UTI
  the editor reads (`public.source-code`, `public.shell-script`,
  `public.python-script`, `public.json`, `public.yaml`, `public.xml`,
  `public.plain-text`, `net.daringfireball.markdown`), each role *Editor* and
  rank *Alternate*, keeping the `public.folder` entry that is already there.
- [x] 1.2 The kinds with no system UTI — `.zig`, `.odin`, `.scad`, `.svelte`
  and whatever else `LanguageRegistry.extensionMap` has that the system does
  not name — declared in `UTImportedTypeDeclarations`, conforming to
  `public.source-code`, so the Finder has something to hang the offer on.
- [x] 1.3 A test over the pair: every extension in `extensionMap` is covered by
  a declared UTI or an imported declaration, and nothing is declared that the
  registry does not know. The list and the plist drift the moment nothing
  compares them.

## 2. The ask

- [x] 2.1 `Settings` gains the answer as three states — unasked, refused for
  now, never ask — because "not now" leaves the settings row offering it and
  "never" silences the ask alone.
- [x] 2.2 The ask itself: the first time a window opens a file of a declared
  kind, once, with *Make Default*, *Not Now* and *Never Ask*. Not at first
  launch — a question about nothing that has happened yet is answered by
  reflex.
- [x] 2.3 Making it the default goes through
  `NSWorkspace.shared.setDefaultApplication(at:toOpen:)`, one call per declared
  UTI, and says what came back rather than assuming.

## 3. The settings row

- [x] 3.1 A row in the settings — and the same one in the settings page in the
  editor, since `SettingsSections` is one list — showing whether Abydos is the
  default, read back from `NSWorkspace.urlForApplication(toOpen:)` rather than
  from what the app once asked for.
- [x] 3.2 Switching it off hands the types back, saying first that the system
  decides what takes them next.
- [x] 3.3 The sentence about the Finder's own *Open in Terminal*: that it is
  Terminal.app's and cannot be redirected, where the service appears, and where
  a shortcut is given to it.

## 4. The terminal service

- [x] 4.1 `NSServices` in the plist — *New Terminal Here*, `NSSendFileTypes`
  `public.folder` and `public.item` — and the provider object registered on the
  app.
- [x] 4.2 The handler: a folder opens the project it belongs to with the
  terminal at that folder; a file opens at the folder holding it; a project
  already open is raised rather than opened twice, through the same door
  `application(_:open:)` uses.

## 5. Proving it

- [x] 5.1 **The ask is not driven, deliberately**, and the code says so:
  `considerAsking` returns at once in a driven run. A capture run must not put
  a sheet in front of the window it is photographing, and must not change which
  application this machine opens `.swift` files with — a stand-in for
  `NSWorkspace` would have been a test of the stand-in. What is checked instead
  is the part that has no window in it: the three-state answer in `Settings`,
  and the declaration itself in `DeclaredFileTypesTests`.
- [x] 5.2 Done by hand on 2026-09-06 against a build under the throwaway id
  `de.rnd7.abydos.editor`, so the machine's real registration was not what was
  being played with:
  - `lsregister -dump` lists 33 claimed UTIs for the bundle, and each imported
    declaration as `active imported trusted`, conforming to
    `public.source-code`.
  - A `.zig` file's `kMDItemContentType` is now
    `de.rnd7.abydos.zig-source` — the system took the declaration.
  - `NSWorkspace.urlsForApplications(toOpen:)` offers Abydos for `.swift`,
    `.zig`, `.yaml`, `.toml` and `.scad`, and **not** for `.psd`, which is the
    non-goal holding.
  - **Two things this found.** `public.toml` and `public.make-source` exist, so
    the system's own types win over an imported declaration and the bundle has
    to name *those* — `.toml` was covered on paper and offered nothing in the
    Finder. And `.ts` is `public.mpeg-2-transport-stream` to macOS, `.mts` an
    AVCHD one: the only way to be offered for a TypeScript `.ts` would be to
    claim video and appear in the *Open With* menu of a recording, so they are
    left alone and the test says why.
- [x] 5.3 `--terminal-service <path>` drives the handler without the Finder:
  on `proj/src` and on `proj/src/a.txt` it opens the project `proj` — the
  enclosing one, through the same door `application(_:open:)` uses — with a
  terminal in the window.

## 6. Finishing

- [x] 6.1 `Scripts/file-size-allowed.txt` raised for `AppDelegate.swift`
  3877 → 3902 (the service provider, its driven door), `LaunchOptions.swift`
  1636 → 1641 and `SettingsWindowController.swift` 1203 → 1249 (the System
  page). `docs/release-notes-0.14.0.md` has the section, including the two
  extensions macOS will not let this app have.
  **The throwaway build was unregistered from Launch Services afterwards**
  (`lsregister -u`), so `de.rnd7.abydos.editor` is not left on this machine
  claiming `.zig`.
- [x] 6.2 Green by their exit codes: `make test` 4137 tests in 526 suites,
  exit 0 with the suite's two standing known issues, load 91.5 over 10 cores;
  `make warnings` exit 0.
  **One failure on the way was somebody else's**: a live test read the Cadova
  examples checkout and asked for its whole executable list in order, so the
  repository gaining a third model failed a test about how two names are spelt.
  It asks for the two spellings now, which was always the claim.
