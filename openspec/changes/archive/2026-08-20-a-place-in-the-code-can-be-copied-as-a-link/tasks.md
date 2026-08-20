## 1. The reference

- [x] 1.1 A type for a place in the code — path, line, and an optional end line
      — that formats itself as `path:12` and `path:12-18`, in `AbydosKit` so
      that its shape is a suite's to hold.
- [x] 1.2 Relative to the project root, and the first of them was a real bug:
      `FilePath.canonical` answers only about files that exist, so a project
      under a symlinked `/tmp` came back `/private/tmp/probe` while a file
      inside it that was not on disk came back `/tmp/probe/…` — the same
      directory, two spellings, no shared prefix, and an absolute path for a
      file plainly inside the project. `canonicalEvenIfMissing` on both sides.
      Also held: a sibling whose name starts the same, a file genuinely outside,
      and a space in the path, left alone rather than escaped., with the cases that bite: a file under a
      symlinked root, a file outside the project, a path with a space in it.
- [x] 1.3 Reading one back, since `Scripts/abydos` and a pasted stack trace both
      produce them: `path:12`, `path:12:5`, `path:12-18`.
- [x] 1.4 Tests over both directions, including the round trip. One assertion
      of mine was wrong rather than the code: `notes:12:42` cannot be told from
      grep's `path:line:column` by shape alone, and the commoner reading wins —
      written down in the test, with a pointer at `Scripts/abydos`, which can
      ask the disk and therefore does better.

## 2. The permalink

- [x] 2.1 `GitForge` builds a URL for a file at a commit, with a line fragment.
- [x] 2.2 The line fragment: GitHub's `#L12` and `#L12-L18`, for the hosts that
      share GitHub's layout — which is the set `GitForge` already claims, GitHub
      and its Enterprise installations, with Gitea and Forgejo working by
      accident rather than by claim. **GitLab and Bitbucket are not guessed at**:
      GitLab spells a range `#L12-18` and Bitbucket differently again, and a URL
      invented for a host nobody tested against is worse than no offer. The
      design's open question is answered that way and no further. its own way — GitHub's `#L12` and
      `#L12-L18` are certain; the others are an open question in the design and
      whatever is decided is written down with what it was checked against.
- [x] 2.3 The head commit, the dirty state of one file, and whether a commit is
      on any remote-tracking branch — all from this checkout, no network.
- [x] 2.4 Tests over the URL building, over a remote this app does not
      recognise, and over a repository with no remote at all.

## 3. Saying what it cannot promise

- [x] 3.1 The unpushed commit: copied anyway, and said.
- [x] 3.2 The dirty file: copied anyway, and said as *which line the link is*,
      not as "uncommitted changes".
- [x] 3.3 Both sentences live in `CodeLink.caveat`, where they can be read
      without a window — the rule `RenameSubject.caveat` already keeps. A clean
      pushed commit says nothing, because a sentence that appears every time is
      one nobody reads.

## 4. The gestures

- [x] 4.1 Copy Reference and Copy Permalink in the editor's context menu, as two
      entries rather than a submenu, and in Edit beside them. The lines they
      name come from `lineSpanForReference`, which has the one rule worth
      having: a selection ending at the very start of line 19 does not name
      line 19, because nobody highlighted it.
- [x] 4.2 Where there is nothing to link to — no checkout, no remote, a remote
      whose host this app does not recognise — the permalink is not built and
      the sentence says which of those it was. The entry itself stays: whether a
      file is in a checkout with a recognised remote is a question with three
      answers and a menu that appears and disappears under the cursor is worse
      than one that explains itself once.
- [x] 4.3 **Decided: ⌘⇧C for the reference, nothing for the permalink.** The
      design asked whether a keystroke is worth spending on a twice-a-week
      gesture. The answer is that the reference is not that gesture — it is the
      string handed to an assistant, done several times in a sitting, and this
      session alone produced dozens of `file:line` references typed by hand. The
      permalink *is* the twice-a-week one: it goes into a message or a bookmark,
      deliberately, and reaching for the menu costs nothing anybody notices.

      What lost: **a keystroke for both**, which would have spent a second
      shortcut on the rarer gesture; and **neither**, which was the honest
      option before the two forms were told apart and is wrong for the frequent
      one. ⌘⇧C is free here and is where IDEA puts "copy reference", which is
      where the muscle memory comes from.

## 5. Following one back

- [x] 5.1 Recognise this app's own permalink, and read the commit, path and line
      out of it — only the `blob` shape it writes. A `tree` URL is a directory
      and a `blame` URL is another page of the same file; following one as
      though it were a permalink is guessing.
- [x] 5.2 Read the file as it was at that commit, take the line, and re-find it
      with `BreakpointAnchors` — reused, not reimplemented.
- [x] 5.3 Say it moved, and say nothing when it did not — "Line 42 at 1c5f368 is
      line 50 now."
- [x] 5.4 A line whose text has gone: land on the number and say what happened.
      And the two cases where there is nothing to compare — a commit this
      checkout has never had, a file that was not in it — take the number at its
      word rather than inventing a line for it.
- [x] 5.5 A `path:line` from anywhere else opens at the number, with nothing
      inferred. **The gesture needed inventing**: with no URL scheme a permalink
      is not clickable into this app, so the pasteboard is the door — Edit ▸ Go
      to Copied Place, ⌘⇧V, which takes either form. A permalink is tried first
      because it is the specific shape: `path:line` would otherwise match the
      tail of any URL with a colon and a number in it.

## 6. Watched

- [x] 6.1 Against a scratchpad repository, never a real checkout: copied
      `Sources/App/Main.swift:7`, said "Copied the reference", and following it
      back landed on Main.swift line 7 with nothing said — which is right, since
      a reference makes no claim about a line having moved.

      **Not through `Scripts/abydos`**, deliberately: that hands the file to
      LaunchServices, which opens the *installed* app — somebody else's copy,
      pointed at whatever it likes. The app's own door was driven instead, which
      is the same parse. The CLI's half is shell and is exercised where the rest
      of that script is.
- [x] 6.2 The permalink's shape: `https://github.com/philipparndt/linkrepo/blob/
      9bbd06a…/Sources/App/Main.swift#L7`, copied through the app.
      **Not opened in a browser**: `philipparndt/linkrepo` is a scratchpad
      repository that exists nowhere, and making it exist would mean publishing.
      The URL's spelling is held by `CodeLinkURLTests` against GitHub's
      documented form.
- [x] 6.3 On an unpushed commit: "Commit 9bbd06a is not on the remote yet, so
      this link will not open for anybody else until it is pushed."
- [x] 6.4 With the file dirty, and the commit now on a remote — a bare
      repository beside it, so nothing left this machine: "This file has changes
      that are not in 9bbd06a, so the line the link opens is the line as of that
      commit, not the line on screen." The unpushed sentence is gone, which is
      the other half of the claim: each is said when it is true and not
      otherwise.
- [x] 6.5 **The point of the whole change, watched.** Three lines added above a
      bookmarked line, the link followed: `LINK followed: Main.swift line 6` and
      "Line 3 at 9bbd06a is line 6 now." The bookmark was to line 3 and the
      editor went to 6, where the text went.

## 7. Finish

- [x] 7.1 The `code-links` capability says what each form promises and what
      happens when a promise cannot be kept.

      **Nothing existing is made untrue.** The capability is new, no other spec
      claims ⌘⇧C or ⌘⇧V, and none says the editor cannot say where a line is.
      What did change is **this change's own spec**, twice, and both are written
      into the delta rather than left as a difference between the words and the
      program:

      - It said the permalink entry *would not be offered* where there is
        nothing to link to. It is offered, and explains itself. Building the
        menu is the moment that decision would have to be made, and whether a
        file is in a checkout with a remote whose host this app knows is three
        questions for git — asked asynchronously, and a right-click cannot wait
        on them. An entry that appears and vanishes under the cursor for reasons
        nobody can see is worse than one that is always there and says why once.
      - It said nothing about *how* a link gets followed, because a permalink is
        not clickable into this app and no scheme is registered. The gesture had
        to be invented: the pasteboard is the door, and the spec now says so.
- [x] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
      `make test exit=0` — 3096 tests in 406 suites, 2 known issues, load 16.3
      over 10 cores. `make warnings exit=0`, four warnings and all four in
      vendored tree-sitter C.
- [x] 7.3 What was ruled out on the way:

      - **An `abydos://` scheme.** The natural home for a clickable link and for
        an anchor, and not taken: it needs a URL type in the bundle, a handler
        treating an inbound URL as a command, and an answer for a link naming a
        project that is not open. Its own item. Both strings here are useful to
        somebody who does not have the app, which is why it could be left.
      - **Putting the anchor in the copied string.** It is what makes
        `path:line` unreadable, and unreadable is the one thing that form cannot
        be. The anchor is recovered instead: given one of its own permalinks,
        the app reads the line as it was at that commit and finds where that
        text is now.
      - **The symbol half of anchoring.** `BreakpointAnchors` can anchor to
        "third line of `TmuxConfig.setStatusHidden`", which survives a function
        moving four hundred lines — and it needs a language server's symbols for
        the file *as it was at a commit*, a document nothing has ever opened.
        The text search alone is the weaker claim, which is what
        `BreakpointAnchors` itself calls the honest fallback.
      - **Guessing a range fragment for GitLab and Bitbucket.** They spell it
        differently and there is no machine here to check against. GitHub's form
        is used for the hosts that share GitHub's layout, which is the set
        `GitForge` already claims.
      - **A copy that fetches or pushes** to make the link work. Pushing is
        somebody's own decision; fetching makes a menu item that sometimes takes
        four seconds.
      - **An absolute path in a reference.** Right on one machine and no other.
        A file genuinely outside the project keeps its absolute path, because a
        `../../..` chain means nothing without knowing where it was written.
      - **`git push` in the tests as a way to make "is on a remote" true** — done
        only to a bare repository in a temporary directory, which is a file copy
        between two folders on this machine, and the shape `GitHistoryTests`
        already uses. Nothing left it.
      - **Driving `Scripts/abydos` for the round trip.** It hands the file to
        LaunchServices, which opens the *installed* app — somebody else's copy,
        pointed wherever it likes. The app's own door was driven instead.
