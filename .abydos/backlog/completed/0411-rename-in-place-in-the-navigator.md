# 411. Rename in place in the navigator

**Return is no longer the key.** Renaming in place is, and works; which key
starts it changed a few days after this landed, and the last section says what
it is now. Everything above that is what was known while this was being done,
and it still says Return throughout — read it as the shape of the gesture
rather than as the binding.

Renaming a file means finding it in the context menu and answering a dialog
(`contextRename`, an `NSAlert` with a text field in it). Everybody who uses a
Mac already knows the other way: select the row, press Return, and the name
turns into a field with the stem selected.

Two things, and the second is the one that matters:

- **Return renames the selected row.** The navigator already takes keys —
  `keyDown` is overridden and there is a testing hook for it — so this is
  which key does what, and making sure Return does not still mean "open" where
  it used to.
- **The editing happens on the row.** Not a sheet in the middle of the window:
  the name is edited where the name is, so the surrounding files stay visible
  and it is obvious what is being renamed.

There is a precedent in this codebase to copy rather than invent: the terminal
tab strip renames in place already — double-clicking a tab puts an `NSTextField`
over it (`renameField` in `BottomPanel`), Return commits, Escape puts it back.
The same shape over an outline row is what this is.

## What has to keep working

`contextRename` is not just a prompt. It validates with `EntryName.problem`,
it moves the file, and it reports what went wrong in a toast. The in-place
editor has to do all of it, and the validation has to happen *before* the field
gives up focus, or a bad name is a rename that silently did not happen.

Worth deciding:

- **What is selected when the field appears.** The Finder selects the stem and
  leaves the extension alone, which is right nearly always and is the detail
  people notice when it is missing.
- **What follows the rename.** An open tab on that file, its position in the
  tree, the git status of the row, and the selection — the tree reloads on the
  filesystem event, so the row is a different object afterwards and the
  selection has to be restored by path, which `restoreSelection(path:)` does.
- **Where else Return should do this.** The changes pane lists files too. Same
  key, same expectation, and it can come later.

Escape cancels. A name that is unchanged is not a rename. An empty one is a
cancel rather than an error, since that is what the field being empty means.

## What the keys are now

Taking Return for renaming followed the Finder, and cost the thing every editor
does with it: *"it is no longer possible to open files with return, which I am
used to from editors"*. Arrowing onto a row already showed the file, so the
argument at the time was that nothing was lost — but showing a file and opening
it are not the same act, and the key that finishes the act was gone. ⌘↓ was the
way back, and nobody who has not read this file knows about ⌘↓.

So, decided and done:

| key | does |
|---|---|
| Return | opens the file, and gives the editor the keyboard |
| F2 | renames in place |
| ⌥Return | renames in place — the same gesture, a second way in |
| ⌘⌫ | moves the selection to the trash |

⌘↓ still opens, though Return does it now: it costs nothing to keep, and hands
that learned it during the week Return did not open anything should not have to
unlearn it.

**Two keys for renaming, deliberately.** F2 is what somebody arrives already
knowing; ⌥Return is for the hands that spent that week with Return meaning
rename. Nothing to remember wrong, at the price of a second binding to keep
working — so both go through `beginRename()`, and neither is a copy of the
other.

**⌘⌫ was reached for repeatedly and did nothing.** It takes the whole
selection, which is the one place several rows makes the work smaller:
`NSWorkspace.recycle` already takes an array (0412). It reads the selection
rather than `contextNodes`, because that starts from `clickedRow` and a row
clicked minutes ago is still the clicked row — the keyboard must never trash
something the keyboard cannot see it is about to trash.

Two things that must not happen, and are checked from the harness rather than
argued about:

- **Nothing on that list fires while the field is up.** The field has the
  keyboard, so these events do not normally arrive at the tree at all — but ⌘⌫
  arriving there would trash the file being renamed, which is not a mistake
  worth leaving one responder-chain accident away. `handleKeyDown` answers
  nothing while `renameField` is set; in the field, Return still commits and ⌫
  still deletes characters.
- **Renaming stays a single-row gesture.** With two rows selected, F2 and
  ⌥Return do nothing rather than renaming whichever came first — the rule
  `beginRename` and `menuNeedsUpdate` already held for Return.

The context menu writes both keys down: "Rename… F2" and "Move to Trash ⌘⌫". A
contextual menu is not in the menu bar so nothing dispatches those — AppKit only
searches the main menu for key equivalents, and `handleKeyDown` is what actually
answers them. They are there to be read, which is the difference between a
shortcut and folklore. An item carries one equivalent, so the menu shows F2 of
the two rename keys.

**A rename bug fell out of testing ⌘⌫ during a rename.** Escape did not cancel
a name that had been *changed*: `endRename` removed the field before forgetting
it, removing a field that is being edited ends the editing there and then, and
the `controlTextDidEndEditing` that follows committed the very name Escape had
just rejected. It renamed `alpha.swift` to `.swift` in front of the harness.
`endRename` now clears `renameField` and `renaming` first — nothing left to
find means nothing left to commit. "Escape cancels", above, was true only for a
name nobody had touched.

The harness drives all of it: `--tree f2,alt-return,cmd-delete,cmd-down,escape`,
and each step prints where the keyboard is and what name the field is holding
beside the selection it already printed.

---

Its number is where it sits in the queue, not what it is worth doing next.
This file was `0411-rename-in-place-in-the-navigator-with-return.md` until the
key stopped being Return.
