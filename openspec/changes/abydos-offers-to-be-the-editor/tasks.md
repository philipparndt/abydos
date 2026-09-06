## 1. What the bundle says

- [ ] 1.1 `Resources/Info.plist` — the document types, one entry per system UTI
  the editor reads (`public.source-code`, `public.shell-script`,
  `public.python-script`, `public.json`, `public.yaml`, `public.xml`,
  `public.plain-text`, `net.daringfireball.markdown`), each role *Editor* and
  rank *Alternate*, keeping the `public.folder` entry that is already there.
- [ ] 1.2 The kinds with no system UTI — `.zig`, `.odin`, `.scad`, `.svelte`
  and whatever else `LanguageRegistry.extensionMap` has that the system does
  not name — declared in `UTImportedTypeDeclarations`, conforming to
  `public.source-code`, so the Finder has something to hang the offer on.
- [ ] 1.3 A test over the pair: every extension in `extensionMap` is covered by
  a declared UTI or an imported declaration, and nothing is declared that the
  registry does not know. The list and the plist drift the moment nothing
  compares them.

## 2. The ask

- [ ] 2.1 `Settings` gains the answer as three states — unasked, refused for
  now, never ask — because "not now" leaves the settings row offering it and
  "never" silences the ask alone.
- [ ] 2.2 The ask itself: the first time a window opens a file of a declared
  kind, once, with *Make Default*, *Not Now* and *Never Ask*. Not at first
  launch — a question about nothing that has happened yet is answered by
  reflex.
- [ ] 2.3 Making it the default goes through
  `NSWorkspace.shared.setDefaultApplication(at:toOpen:)`, one call per declared
  UTI, and says what came back rather than assuming.

## 3. The settings row

- [ ] 3.1 A row in the settings — and the same one in the settings page in the
  editor, since `SettingsSections` is one list — showing whether Abydos is the
  default, read back from `NSWorkspace.urlForApplication(toOpen:)` rather than
  from what the app once asked for.
- [ ] 3.2 Switching it off hands the types back, saying first that the system
  decides what takes them next.
- [ ] 3.3 The sentence about the Finder's own *Open in Terminal*: that it is
  Terminal.app's and cannot be redirected, where the service appears, and where
  a shortcut is given to it.

## 4. The terminal service

- [ ] 4.1 `NSServices` in the plist — *New Terminal Here*, `NSSendFileTypes`
  `public.folder` and `public.item` — and the provider object registered on the
  app.
- [ ] 4.2 The handler: a folder opens the project it belongs to with the
  terminal at that folder; a file opens at the folder holding it; a project
  already open is raised rather than opened twice, through the same door
  `application(_:open:)` uses.

## 5. Proving it

- [ ] 5.1 The driven part: the ask's three answers and what each leaves behind
  in the settings, and the settings row reading Launch Services rather than the
  app's own memory — with a stand-in for `NSWorkspace` so the run does not
  change the machine's real handlers.
- [ ] 5.2 The part a driven run cannot do, done by hand and written down:
  `lsregister -dump` showing the declared types after a build, the Finder's
  *Open With* listing the app for a `.swift`, and the service appearing in the
  Finder's menu — against the app under a **throwaway bundle id**, so the
  machine's real `de.rnd7.ideai` registration is not what is being played with.
- [ ] 5.3 The service handler driven directly on a folder and on a file, since
  the handler is reachable without the Finder.

## 6. Finishing

- [ ] 6.1 `Scripts/file-size-allowed.txt` for what grew, reasons said aloud;
  `docs/release-notes-0.14.0.md` given the section, including what macOS does
  not allow.
- [ ] 6.2 `make test` and `make warnings`, both clean by their exit codes.
