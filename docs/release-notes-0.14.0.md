# Abydos 0.14.0

Secrets and trust, and the chrome that had stopped explaining itself.

## A project is trusted before it runs

Opening a folder used to run code from it — on the open, not on a press:
configurations discovered from a `Makefile` and a `launch.json`, a language
server started from the project's own tree, a devcontainer, `.git/hooks` on a
commit. A repository cloned to read got the trust its owner's code gets.

Now nothing of a project's runs by itself until you say so, and a strip at the
top of the window says which project and what waits.

- **Reading is untouched**: tree, editor, syntax, search, git panes, history,
  diffs, blame, previews.
- **Held back**: run, debug, build; make, gradle, maven; devcontainers;
  language servers; agents; the environment its files ask for; its git hooks.
- **The terminal still opens** — it is your shell, and what you type in it is
  your choosing. `DIRENV_DISABLE` is set so its `.envrc` does not run behind
  you.
- **A commit declines the project's hooks** and says so, rather than being
  refused.
- **Environment variables are dropped, not filtered.** `SOPS_AGE_KEY_CMD` is a
  command sops runs, `GIT_SSH_COMMAND` one git runs — the dangerous ones do not
  look dangerous.
- **Trust is a choice of scope** from the strip's dropdown or File ▸ Project
  Trust: this project, the folder it sits in, or where a clone says it came
  from — one owner, or a whole enterprise host. Never the whole of `github.com`.
  The same menu takes it back.
- Remembered by folder in this app's support directory, never inside the
  project. A remote is the repository's own claim, which the menu says before
  granting it.

Not a sandbox: it decides what starts, not what a trusted build then does. Not
a scanner: nothing guesses which projects look safe.

## A SOPS file decrypts from the status bar

A chip beside the secrets lock on a SOPS-encrypted file: press it to decrypt
into the editor, ⌘S to encrypt and save. The values arrive revealed and the
lock shuts them again.

- **Nothing decrypted touches a disk** — no `.dec`, no temp file. Auto-save is
  off, no language server hears it, the session records the tab and not its
  text, and a file that changed underneath is refused rather than overwritten.
- **A save that changed nothing writes nothing.** `sops --encrypt` takes a
  fresh data key each run, so an unedited buffer used to rewrite every line.
- **Edits survive a project switch**, in memory, and ⌘Q asks per file with a
  Cancel that stops the quit.
- Two things to know: a whole-file encrypt changes every value's ciphertext,
  and a `SOPS_AGE_KEY_FILE` set in a shell profile is not seen by a GUI app.

## A secret file says whether git can see it

The editor covered a `.env`'s values and said nothing about the worse
exposure. Now, beside the lock: *Not in .gitignore*, or *Committed to git* for
the case a `.gitignore` line can no longer fix.

- Pressing it offers to add the file to `.gitignore`, and the notice goes.
- Nothing is said for a file git ignores, or outside a repository.
- **The chip's other side**: a plaintext file matched by a rule in the
  project's `.sops.yaml` offers *SOPS · encrypt*, in place, in one press.

## ⇥ follows the file's own indentation

⇥ used to insert a tab whatever the file. A file's habit is now read at open —
tabs, or spaces and how many — and ⇥, ⇧⇥, block indent and return all follow
it.

- The footer says *Tabs* or *Spaces: 2*, between the caret position and the
  language.
- Its menu converts the file, level by level, in one edit: one ⌘Z takes the
  file and the chip back together.
- Return's auto-indent now takes its **width** from the file too, so a
  two-space file no longer indents by the setting's four.

## A tag can be deleted, here and on the remote

*Delete Tag…* on a tag row, or ⌘⌫, for one tag or several.

- The remote is a separate tick, off by default and named after the remote.
- The local delete runs first, so a refusing remote leaves *Deleted here, still
  on origin* with git's reason — not one "could not delete" over a half-done
  pair.
- A selection holding a branch and a tag shows the item disabled: two
  questions, two sheets.

## Every action in the chrome says what it does

The terminal strip's controls answered the pointer; nothing else did. Now the
left rail, the pane headers, the run and debug controls and the panes' own
buttons — git, scratches, review, debug — all draw a hover and show the app's
own tooltip.

- A tip's keyboard shortcut is read from the menu bar, so it cannot promise a
  key the menu does not have. That found one: ⌃R belongs to *Run…*, so the play
  button has no key of its own.
- The scratches and debug buttons stopped being system bezels on the way, which
  also settles their height at a large zoom.

## The Finder knows what this app opens

The bundle declared one thing — a folder — so a source file's *Open With* menu
had never heard of Abydos.

- It is now offered for what the editor actually reads, as an *alternate*: an
  offer in the menu, claiming nothing at installation.
- The first source file you open asks once whether it should be the default,
  with *Not Now* and *Never Ask* meaning what they say. Settings ▸ System has
  the same switch, read back from Launch Services rather than from what the app
  once asked for.
- **Right-click a folder in the Finder ▸ Services ▸ New Terminal Here** opens
  the project with its terminal there. The Finder's own *Open in Terminal*
  belongs to Terminal.app and macOS lets no application take it — a service
  beside it is the whole of what is on offer, and the settings page says so.
- Two gaps on purpose: `.ts` and `.mts` are an MPEG-2 transport stream to
  macOS, and claiming that would put this editor in the *Open With* menu of a
  video.

## ⇧⌘P opens where you are looking

⇧⌘A centred its list on the window; ⇧⌘P opened its own in the top-left corner.
Now the key's palette opens centred over the window that answered it, as a
child of it. Clicking the project pill still opens the list at the pill.
