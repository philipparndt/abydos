<!-- What this item changes about `usages`.

     "Every move ends with the keyboard back in the rows" became untrue:
     a list pushed out of the sidebar to make room for the other one is a
     move nobody asked for, and it must not take the keyboard from the
     list arriving in its place. Two sentences added; everything else is
     the requirement as it stood.
-->

## MODIFIED Requirement: The keyboard stays in the list in every home, including beside a terminal

A list arrives with the keyboard in it wherever it is put, and every move
somebody asks for ends with the keyboard back in the rows — so ↓ walks the list,
␣ ticks a row and ⌘Z takes the marking back, in the panel, under the project
view, beside a terminal and in a window alike. Being moved is not being finished
with.

The home beside a terminal is the one this has to be said about. A terminal
takes every keystroke it is given, and the pane put beside one is not a terminal:
a list arriving there while the shell held the keyboard would send ↓ to the
scrollback and ␣ to the prompt. So a list put beside a terminal takes the
keyboard from it, and the terminal beside it gets nothing until somebody clicks
it.

One move is not asked for and does not take the keyboard: the sidebar holds one
list, so sending one there sends the other back to the panel. That list is being
evicted rather than reached for, and the keyboard belongs to the one arriving —
which is the one being looked at.

⇥ hands the keyboard to the editor from every home, the window included. A list
expanded into a window of its own is a second window and is the key one while
somebody works the list, so ⇥ there makes the project window key as well as
putting the caret in the editor — otherwise the file would open, the caret would
blink in it, and every keystroke would go on reaching the list.

The one exception to the whole of this is `search.md`'s: a search *asked for*
with ⇧⌘F puts the keyboard in its query field instead, in every home, because
asking is typing a question.

### Scenario: ↓ and ␣ at a list beside a live shell

- **Given** a usages list beside a terminal with a shell running in it
- **When** ↓ and ␣ are pressed
- **Then** the selection moves down the list and that row is marked done, and
  nothing at all is typed at the shell

### Scenario: ⇥ from a list in a window of its own

- **Given** a usages list in a window of its own, with the keyboard in it
- **When** ⇥ is pressed
- **Then** the usage opens in the project window's editor, that window is the key
  one, and the next keystroke reaches the editor rather than the list

### Scenario: the list that is pushed out

- **Given** search results under the project view
- **When** Find Usages sends a usages list there too
- **Then** the search results go back to the panel and the usages list has the
  keyboard, so ↓ walks the usages
