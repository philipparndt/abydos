## 1. The reference

- [ ] 1.1 A type for a place in the code — path, line, and an optional end line
      — that formats itself as `path:12` and `path:12-18`, in `AbydosKit` so
      that its shape is a suite's to hold.
- [ ] 1.2 Relative to the project root, with the cases that bite: a file under a
      symlinked root, a file outside the project, a path with a space in it.
- [ ] 1.3 Reading one back, since `Scripts/abydos` and a pasted stack trace both
      produce them: `path:12`, `path:12:5`, `path:12-18`.
- [ ] 1.4 Tests over both directions, including the round trip.

## 2. The permalink

- [ ] 2.1 `GitForge` builds a URL for a file at a commit, with a line fragment.
- [ ] 2.2 The line fragment each forge spells its own way — GitHub's `#L12` and
      `#L12-L18` are certain; the others are an open question in the design and
      whatever is decided is written down with what it was checked against.
- [ ] 2.3 The head commit, the dirty state of one file, and whether a commit is
      on any remote-tracking branch — all from this checkout, no network.
- [ ] 2.4 Tests over the URL building, over a remote this app does not
      recognise, and over a repository with no remote at all.

## 3. Saying what it cannot promise

- [ ] 3.1 The unpushed commit: copied anyway, and said.
- [ ] 3.2 The dirty file: copied anyway, and said as *which line the link is*,
      not as "uncommitted changes".
- [ ] 3.3 Both sentences live where they can be read without a window.

## 4. The gestures

- [ ] 4.1 Copy Reference and Copy Permalink in the editor's context menu, as two
      entries rather than a submenu.
- [ ] 4.2 The permalink entry is absent where there is nothing to link to.
- [ ] 4.3 Decide the keystroke question the design leaves open — ⌘⇧C or nothing
      — and write down what lost.

## 5. Following one back

- [ ] 5.1 Recognise this app's own permalink, and read the commit, path and line
      out of it.
- [ ] 5.2 Read the file as it was at that commit, take the line, and re-find it
      with `BreakpointAnchors` — reused, not reimplemented.
- [ ] 5.3 Say it moved, and say nothing when it did not.
- [ ] 5.4 A line whose text has gone: land on the number and say what happened.
- [ ] 5.5 A `path:line` from anywhere else opens at the number, with nothing
      inferred.

## 6. Watched

- [ ] 6.1 Against a scratchpad copy, never a real checkout: copy a reference,
      paste it into `abydos`, land on the line.
- [ ] 6.2 Copy a permalink on a clean pushed commit and open it in a browser.
- [ ] 6.3 Copy one on an unpushed commit, and read the sentence.
- [ ] 6.4 Copy one with the file dirty, and read the sentence.
- [ ] 6.5 Add lines above a bookmarked line, follow the link, and watch it land
      on the text rather than on the number — and say so.

## 7. Finish

- [ ] 7.1 The `code-links` capability says what each form promises and what
      happens when a promise cannot be kept. Name any sentence this makes
      untrue.
- [ ] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 7.3 Write down what was ruled out on the way.
