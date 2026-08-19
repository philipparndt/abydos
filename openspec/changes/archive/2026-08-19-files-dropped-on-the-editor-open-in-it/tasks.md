## 1. See what happens now

- [x] 1.1 A driver verb that drops a file on the editor, since a real drag
      cannot be scripted: put a file URL on a pasteboard and hand it to the drop
      view the way AppKit would.
- [x] 1.2 Drive it before changing anything and record that nothing opens, so the
      after-state is a comparison rather than a claim. Measured by disabling the
      one step the fix adds: `DROP offered: other` — that is `.move`, which a
      Finder drag never permits — and `DROP accepted: false`, tabs unchanged.
- [x] 1.3 Say what `draggingEntered` answers today for a drag carrying a file
      URL. It returns `.move` unconditionally, and the tree already carries the
      lesson that answering with an operation the source never permitted is a
      drop that quietly does nothing.

## 2. The editor takes files

- [x] 2.1 The group registers `.fileURL` beside `EditorTabDrag.pasteboardType`.
- [x] 2.2 `draggingEntered` and `draggingUpdated` answer from what the drag
      actually permits, rather than `.move` for everything.
- [x] 2.3 `performDragOperation` reads file URLs where there is no tab payload,
      and declines anything that is neither.
- [x] 2.4 A URL that is not a file — a web address from a browser — is declined
      rather than opened.
- [x] 2.5 Opening goes through the path `openFromTerminal` already uses, so the
      panel makes room and the tree is told, and there is one function rather
      than two that agree today.

## 3. What a drop means

- [x] 3.1 The window's project does not change. Assert it: the tree, git, the
      run configurations and the language servers all belong to it.
- [x] 3.2 Several files open several tabs, in order, last in front, none of them
      provisional.
- [x] 3.3 A folder opens as a project, through `open(projectAt:from:)` with this
      window as the source, so the new-window setting and the raise-if-already-
      open behaviour are the ones that already exist.
- [x] 3.4 A drag holding both treats each as it would have been treated alone.
- [x] 3.5 The zone overlay stays a tab's business: while a file is over the
      group the highlight is the whole group, so what is shown is what happens.

## 4. Tests as claims

- [x] 4.1 Whatever can be decided without a window is decided without one —
      which URLs are files, what a mixed drag separates into, what operation a
      drag permits — and those get tests:
      `aWebAddressIsNotAFileToOpen`,
      `aMixedDragSeparatesFoldersFromFiles`.
- [x] 4.2 The rest is checked by driving, and the report says what it saw.

## 5. Watched

- [x] 5.1 A file from outside the project, dropped, against a scratchpad copy —
      never a real checkout. The house rule exists because an agent renamed a
      file in a real `~/.config/zshutil`.
- [x] 5.2 The project before and after, to show it did not move.
- [x] 5.3 Three files at once, photographed: three tabs, the last in front.
- [x] 5.4 A folder, opening as a project.
- [x] 5.5 A tab dragged between groups still splits, unbroken.

## 6. Finish

- [x] 6.1 `.abydos/backlog/spec/editor.md` says a file dropped on a group opens
      in it and that the project does not move. Name any sentence this makes
      untrue.
- [x] 6.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 6.3 Write down what was ruled out, including opening a dropped file into a
      split on the strength of which half the pointer was over.
