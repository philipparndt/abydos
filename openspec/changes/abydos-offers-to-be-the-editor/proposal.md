## Why

**The Finder does not know this app opens files.** The bundle declares one
document type — `public.folder`, as an *Alternate* viewer — so a source file's
*Open With* menu does not list Abydos, dragging a `.swift` onto the Dock icon
does nothing, and double-clicking a file in the Finder opens whatever was
registered years ago. Everything behind that is already written: Launch
Services' `application(_:open:)` is implemented, opens a folder as a project
and a file inside the project that encloses it, and `abydos <file>` from a
terminal has done the same for months. What is missing is the declaration, and
somebody being asked.

The same gap the other way round: the app is a terminal-first IDE whose
terminal cannot be reached from the Finder at all. *Open in Terminal* there is
Terminal.app's own, and a folder somebody is standing in front of is exactly
where a terminal is wanted.

Asked for on 2026-09-06: "abydos should register itself as editor for source
files. It should ask if it shall do this. It should also be possible to
register abydos as terminal (Finder / 'Open in Terminal')".

No originating backlog item: asked for directly.

## What Changes

- **The bundle says what it can open.** The document types grow from one
  folder entry to the kinds of file this editor handles — source code, plain
  text, and the structured formats it has previews and grammars for — declared
  as an *Editor* and ranked *Alternate*, so the app appears in *Open With* and
  can be chosen, without claiming anything it was not given.
- **It asks before it takes anything.** Once, and not at first launch — the
  first time somebody opens a source file in a window, which is the moment the
  question is about something they were doing. Three answers: make it the
  default for this kind of file, not now, and never ask again. What was chosen
  is remembered, so the question is asked once whatever the answer.
- **The same choice lives in the settings**, where it can be made or undone
  later without waiting for the app to ask: which kinds of file Abydos is the
  default for, and a switch that hands them back.
- **Abydos offers a terminal to the Finder.** A service — *New Terminal Here*
  — on a folder, opening the project's window with its terminal at that
  folder, and on a file, at the folder holding it. It joins the Finder's
  *Services* menu and the right-click menu there, where a shortcut can be
  given to it in System Settings.
- **What cannot be done is said rather than implied:** the Finder's own
  *Open in Terminal* item belongs to Terminal.app and cannot be pointed
  somewhere else by any application. A service beside it is the whole of what
  macOS offers, and the settings text SHALL say so rather than leaving
  somebody hunting for a switch that does not exist.
- **Not proposed:** claiming the default handler for a kind of file without
  being asked, registering for kinds this editor cannot show, a Finder
  extension, or anything that changes another application's settings.

## Capabilities

### New Capabilities

- `system-integration`: what the Finder and Launch Services are told this app
  opens, when and how somebody is asked to make it a default, what is
  remembered about the answer, and the terminal service on a folder.

### Modified Capabilities

<!-- None. `editor` describes what happens once a file arrives — a dropped
folder opening as a project, a dropped file opening as a tab — and this is
about the file arriving at all. -->

## Impact

- `Resources/Info.plist` — the document types, and the `NSServices` entry that
  puts *New Terminal Here* in the Finder's menu. Both are declarations rather
  than code, and both are read by Launch Services when the bundle is
  registered.
- `Sources/AbydosApp/AppDelegate.swift` — the services provider object, the
  handler behind the menu entry, and the ask when a source file is first
  opened.
- `Sources/AbydosKit/Settings/Settings.swift` — what was answered, so it is
  asked once; the settings page reads the same value.
- `Sources/AbydosApp/Settings/SettingsSections.swift` — the row where the
  choice can be made later, with the sentence about the Finder's own item.
- No new dependency: `NSWorkspace.setDefaultApplication(at:toOpen:)` is the
  system's own, and this app's minimum is already macOS 14.
