## Context

Everything behind the Finder is already written and reachable from everywhere
but the Finder. `application(_:open:)` opens a folder as a project and a file
in the project that encloses it; `abydos <file>` and `abydos <dir>` from a
terminal go through the same door; a drop on an editor group is specified in
`editor` down to the order files and folders arrive in.

What the bundle declares is one entry: `public.folder`, role *Viewer*, rank
*Alternate*. So Launch Services believes this application opens folders and
nothing else, and a `.swift` in the Finder has never heard of it.

`LanguageRegistry.extensionMap` is the list of what the editor actually reads —
some forty-five extensions across twenty-odd grammars — and is the honest
answer to "what can this open", as against "text, probably".

The terminal side has no macOS hook to take over: the Finder's *Open in
Terminal* is Terminal.app's, wired to it by the system. What every other
terminal does — iTerm among them — is advertise a *service* on a folder, which
the Finder shows in its *Services* submenu and which System Settings can give
a keyboard shortcut.

## Goals / Non-Goals

**Goals:**

- The Finder can open a source file with this app: *Open With* lists it, and it
  can be made the default for a kind of file if somebody says so.
- The question is asked once, at a moment it is about, and is answerable with
  "never ask again".
- The Finder can put a terminal at a folder without anybody typing a path.
- What macOS does not permit is said in the app rather than left as a switch
  somebody hunts for.

**Non-Goals:**

- Not claiming default handlers at install or at first launch. An application
  that takes `.json` from somebody's editor without asking is one they
  uninstall.
- Not registering for kinds it cannot read: a `.psd` in *Open With* is a
  promise the editor cannot keep.
- Not writing another app's settings, and not a Finder extension: an extension
  is a second binary, a second signing identity and a second thing to keep
  alive, for a menu item a service already provides.
- Not replacing the Finder's *Open in Terminal*, which is not offered by macOS
  to anybody.

## Decisions

### The declaration says what the editor reads, in the system's own vocabulary

The document types become the union of what `LanguageRegistry` knows and what
the previews handle, expressed as UTIs where the system has one —
`public.source-code`, `public.shell-script`, `public.python-script`,
`public.json`, `public.yaml`, `public.xml`, `public.plain-text`,
`net.daringfireball.markdown` — with `LSItemContentTypes` naming those rather
than a hundred extensions. A handful this app reads have no system UTI
(`.zig`, `.odin`, `.scad`, `.svelte`); those are declared by extension in an
`UTImportedTypeDeclarations` block that conforms them to `public.source-code`,
which is what a system with no opinion about a file type wants to be told.

Every entry is role **Editor** and rank **Alternate**. Rank is the whole
politeness of this: *Owner* claims the type, *Alternate* offers.

*Ruled out:* declaring `public.data` or `public.item` — that puts this app in
the *Open With* menu of a video, which is the "opens everything, reads
nothing" behaviour the request explicitly does not describe.

### The ask happens when a source file is first opened, not at launch

A first-launch dialog is asking about something nobody has done yet, and every
first-launch dialog is answered by reflex to get rid of it. The first time a
window opens a file whose type is one of the declared ones — however it was
opened — the app asks once: *Make Abydos the default for source files?* with
**Make Default**, **Not Now** and **Never Ask**.

What was answered is one setting with three states, because "not now" and
"never" are different: the first leaves the question askable from the settings
page and the second silences the ask itself. Neither writes a handler.

*Ruled out:* asking per file type — there are eight UTIs and nobody wants eight
dialogs. The ask is about the group; the settings page is where a type is
picked out of it.

### Making the default is one system call, and its refusal is the system's

`NSWorkspace.shared.setDefaultApplication(at:toOpen:)` — macOS 14, which this
app already requires. macOS may put its own confirmation in front of it; that
is the system's dialog and the app does not try to predict it, but the settings
row is read back afterwards from `NSWorkspace.urlForApplication(toOpen:)` so
what the page shows is what Launch Services believes rather than what the app
asked for.

### The terminal is a service on a folder

`NSServices` in the bundle: *New Terminal Here*, `NSSendFileTypes` of
`public.folder` and `public.item`, and a provider object on the app. A folder
opens the project it belongs to with the terminal at that folder; a file opens
at the folder holding it, because "here" is where the thing is.

The settings page carries the sentence that the Finder's own *Open in Terminal*
belongs to Terminal.app and cannot be redirected — with where the service
appears and where a shortcut is given to it, which is the actual answer to what
was asked for.

*Ruled out:* a login-item helper that watches for a keystroke — the shortcut is
System Settings' job, and a background process to duplicate it is a background
process to explain.

## Risks / Trade-offs

- [A service that opens a whole IDE from a folder is slow next to Terminal.app]
  → it opens the project the folder is in, which is what this app is for; the
  service's name says *terminal* and the window comes up with the panel in
  front.
- [Declaring types the editor reads badly] → the list is `LanguageRegistry`'s
  own, so what is claimed and what is highlighted are the same set by
  construction, and a type added to one is the same edit as adding it to the
  other.
- [Somebody makes it the default and regrets it] → the settings row hands the
  types back to whatever the system's next choice is, and says so before it is
  pressed.
- [The ask arriving in the middle of something] → once, on a file that was
  opened deliberately, with a *Never Ask* that means it.

## Open Questions

None: the API is the system's, the list is the registry's, and the Finder's own
terminal item is not on offer to anybody.
