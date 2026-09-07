## Context

`Sops.decrypt` runs the `sops` binary with the app's environment and a
login-shell `PATH` (the 0.16.1 fix), reads stdout as the plaintext and shows
stderr in a toast on failure. sops does not decrypt PGP itself: it runs
`gpg --decrypt` (or the binary `SOPS_GPG_EXEC` names) as a child, and gpg
asks the agent for the key's passphrase, which the agent asks a pinentry for.
Without a tty and without a graphical pinentry the ask cannot happen, and gpg
reports it in its own words — *Inappropriate ioctl for device*, *No pinentry*,
*Operation cancelled*, *decryption failed: No secret key* — which sops passes
on. The chip lives in `EditorStatusView`, a drawn view with a rect per chip
and a press handler, in the same bar as the line and column.

## Goals / Non-Goals

**Goals:**

- A passphrase typed where the chip is, in the bar, and the decrypt going
  through with it.
- The passphrase touching nothing but gpg: not the environment, not the
  arguments, not a file, not a log, not a toast.
- No question when none is needed.
- Not asking again within a sitting.

**Non-Goals:**

- age identities with a passphrase: sops reads plain identities only.
- Presetting the agent (`gpg-preset-passphrase` needs
  `allow-preset-passphrase`, which is off by default).
- Encrypting with a passphrase: PGP encryption uses the public key and
  asks for nothing.
- Storing the passphrase in the keychain. Wanted by some, a decision of its
  own, and the keep-for-the-sitting is what makes it not urgent.

## Decisions

### The first attempt is the attempt there is today

Pressing the chip runs sops exactly as now. An agent with the passphrase
cached, a `pinentry-mac` that is installed and configured, an age key — none
of them should see a field. Only when the decrypt fails *and* gpg's words are
the shape of a missing passphrase does the field appear; any other failure
keeps the toast.

*Ruled out:* always asking first. Everybody whose setup works would be
typing a passphrase they never needed, and would answer the field by reflex.

### The passphrase goes to gpg on a file descriptor, through a wrapper

sops runs whatever `SOPS_GPG_EXEC` names. The app writes, once, a wrapper
script under its own Application Support directory:

    #!/bin/sh
    exec gpg --batch --pinentry-mode loopback --passphrase-fd 3 "$@"

and runs sops with `SOPS_GPG_EXEC` pointing at it and a pipe whose read end
is file descriptor 3, `FD_CLOEXEC` cleared so it survives the two execs (sops
is Go, which leaves inherited descriptors alone; gpg inherits from sops). The
app writes the passphrase to the pipe's write end and closes it. gpg reads it
from fd 3 and nothing else ever sees it: not `ps`, not the environment a
child could dump, not a file a crash could leave.

The wrapper itself holds no secret; it is a fixed script and its path is what
the environment variable carries.

*Ruled out:* `--passphrase-file` on a temporary file — a secret on disk for
the length of a decrypt, and a crash leaves it there. *Ruled out:* `--passphrase`
as an argument — visible in `ps`. *Ruled out:* an environment variable — gpg
has no such option, and a child's environment is readable.

### The field is the chip's own place in the bar

While a passphrase is being asked for, `EditorStatusView` hides the chip and
lays a secure field over its rect, sized by the bar's font through the
scaled-controls library (a measured member: AppKit's `NSSecureTextField`
given its font and height from the theme, never a `controlSize`). Its
placeholder names the key when gpg said which — *Passphrase for 0x…* — and
otherwise the file. gpg's sentence goes in the tooltip, not beside the field;
the bar is one line. Return retries the decrypt with the field's text; Escape
puts the chip back; a wrong passphrase — gpg says *Bad passphrase* — keeps
the field with that sentence as its placeholder. The field's text is read
once and the field cleared.

*Ruled out:* a sheet or an alert. The person asked for the bar, and a modal
over a decrypt that fails on a typo is the worse experience.

### The keep is in memory, for the sitting

`Passphrases` is a process-wide map from a key's identity — gpg's key ID
when it named one, else the file's project root — to the passphrase that
worked, cleared at quit and by *Lock* with ⌥ held. Nothing writes it. A
decrypt that fails for want of a passphrase is retried with the kept one
before the field is shown, so lock-and-decrypt-again does not ask.

*Ruled out:* per file. The same key unlocks every file in the project, and
asking per file is asking the same question by another name.

### The shape of the failure is read from gpg's words

`Sops.needsPassphrase(stderr:)` says yes for the phrases gpg and the agent
produce when no pinentry can run: *Inappropriate ioctl for device*, *No
pinentry*, *problem with the agent*, *Operation cancelled* against a PGP data
key, *Bad passphrase*. Recorded messages from gpg 2.4 back the test. A message
outside the list keeps the toast, which says the words in full.

## Risks / Trade-offs

- [Go closing inherited descriptors] → Go marks descriptors *it* opens as
  close-on-exec and leaves inherited ones alone; the fd plumbing test runs a
  fake sops written in sh and, where the machine has it, the real sops, so the
  claim is checked rather than believed.
- [A pinentry-mac that would have worked, now bypassed] → it is not: loopback
  is only used on the retry, after the first attempt without it failed.
- [Somebody reading the passphrase from the pipe] → the pipe exists for the
  length of one sops run, inside one process tree, with the write end closed
  the moment the passphrase is written.
- [`--batch` refusing a gpg configured to require a pinentry] →
  `allow-loopback-pinentry` is on by default in gpg-agent since 2.1.12; a
  gpg-agent.conf that turns it off gets gpg's own sentence in the field.
- [The driven proof needing a key] → a fake sops and a fake gpg, in sh, under
  the scratchpad, print what was read on fd 3 without printing it, and a real
  key made with `gpg --batch --gen-key` in a throwaway `GNUPGHOME` runs when
  gpg and sops are on the machine.

## Open Questions

- **The keychain.** Whether a passphrase that worked should be offered to the
  keychain, as git credential helpers do. Not here; the sitting keep decides
  whether anybody misses it.
