<!-- What this item changes about `language-servers`. Folded into
     .abydos/backlog/spec/language-servers.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A tool Xcode owns comes from Xcode, not from the PATH
       One search finds every tool this program runs
       A language server is kept until the app goes, and no longer
       One server per project per server, not per language
       What is running can be seen and stopped
       A project chooses which server answers for a language
       A chosen server that cannot be started says so
       The Java debugger belongs to the server that hosts it
       Choosing where a server comes from takes effect now
       The footer says which server is answering, and from where
       A server that started and is not answering says so above the file
-->

## ADDED Requirement: A server can change the code, and rename is what it is asked for

Everything else this program asks a language server is a question. Renaming a
symbol is the first thing it asks that changes files, and it changes many of
them at once: the answer is a *workspace edit*, and one of those from a real
project arrives about a hundred files in six directories, none of which anybody
had open.

Rename ▸ from the code's context menu, or ⇧F6, which is IDEA's. **The new name
is typed where the old one is** — a field laid over the symbol, in the text,
scrolling with it — rather than in a dialog. It is the navigator's in-place
rename on a row, one layer in: the thing being renamed is on screen, the new
name goes where the old one is, and the rest of the window carries on. Return
takes it, Escape drops it, clicking away takes it, and a name that is refused
leaves the field standing with the text still in it, because a name that is not
allowed is a typo far more often than it is a change of mind.

### Scenario: renaming a symbol used in several files

- **Given** a project with a server running, and a symbol used in three files of
  which one is open
- **When** it is renamed from the editor
- **Then** all three files say the new name
- **And** the open one says it in its editor as well as on disk

### Scenario: the caret is not on anything renameable

- **Given** the caret on a bracket
- **When** a rename is asked for
- **Then** nothing is said and no field appears

## ADDED Requirement: A rename that cannot be offered is not offered

An offer that fails is worse than an absence. Whether renaming is possible is
settled before anything appears on screen, from two different sources and in
this order: **what the server said it can do at the handshake**, which is a fact
about the server, and then **`prepareRename`**, which is a fact about the
position. A server that does not rename is never asked.

Three ways of not being able to, and only one of them is said out loud. No
server running for the file is silent, because that is most files in most
projects and what there is to say about a missing server is the strip above it.
The server's own "nothing here" is silent, because that is what the caret being
on a bracket looks like every time. **A server that is running and does not
rename says so, by name**, because that is a fact about the server somebody
chose and they can choose another.

`prepareRename` is asked only of servers that say they support it. Several
servers rename and answer `MethodNotFound` to that question, which arrives as a
refusal indistinguishable from a symbol that cannot be renamed; for those, the
word under the caret is what the field opens on, which is the answer the editor
had before it asked anything.

### Scenario: a server that does not rename

- **Given** a running server whose capabilities do not offer rename
- **When** a rename is asked for
- **Then** it says that server does not rename, and names it
- **And** no field appears

### Scenario: a server that renames but is not asked first

- **Given** a running server that renames and does not offer `prepareRename`
- **When** a rename is asked for with the caret in a word
- **Then** the field opens on that word

## ADDED Requirement: A rename says which kind of rename it is

A language may have more than one server and they do not know the code the same
way. One reads types; another matches names over what it indexed. For a question
that is a trade somebody made on purpose — a wrong answer costs a keystroke. For
an answer that *changes forty files*, it is the one thing they need to know
before they accept it, and 0449 made it possible for a project to be pointed at
such a server without the person at the editor knowing.

So a rename offered by a server that reads text rather than types says so, under
the field, **before the name is typed**. A warning that arrives with the result
is a warning about something that has already happened, and a rename is undoable
where somebody's confidence in the tool is not.

### Scenario: a project pointed at the syntactic Java server

- **Given** a Java project whose `.abydos/tools.json` chooses the server that
  matches names rather than types
- **When** a symbol in it is renamed
- **Then** the field says that unrelated things of the same name will be renamed
  too, and says it before the name is typed

## ADDED Requirement: A workspace edit is worked out in full before anything is written

A workspace edit is not one change, it is forty, and the failure that matters is
twenty files written and the twenty-first refused — which leaves a project that
compiles nowhere and no record of how it got there. The answer is in three
layers, and the first is by far the most important.

**Everything is read, edited and checked while nothing has been written.** A
file that is not there, a range the file does not have, two edits over one
character, a rename onto a name something already holds: all of them are known
before anything is touched. **One refusal and nothing happens at all** — the
person is told which file and why, their project is exactly as it was, and they
can fix that one thing and ask again. Half a refactoring is not a lesser good
than a whole one, it is worse than none.

**A write that fails anyway is put back**, from the previous contents worked out
in the first step — which is the same information the undo entry holds, so the
rollback and ⌘Z are one mechanism rather than two that can come to disagree.

**A rollback that cannot finish names every file on both sides**, by name and
not by count. It is the floor, it takes the file system refusing twice, and when
it happens being exact is the only thing left worth doing.

An edit this program cannot read in full is refused in full. An entry of a kind
it has never heard of, dropped quietly, would apply most of somebody's
refactoring and leave the rest — which is the halfway state all of this exists
to avoid.

### Scenario: one file of forty cannot be written

- **Given** a rename that would change forty files, one of which is read-only
- **When** it is applied
- **Then** nothing is changed at all, and it says which file stopped it

### Scenario: a file that changed under the server

- **Given** a rename whose edits name a place the file no longer has
- **When** it is applied
- **Then** it says the server and the file no longer agree about that file
- **And** no other file in the edit is changed

## ADDED Requirement: A workspace edit reaches open documents through the rope, and files that move

A file with an editor on it cannot be written behind the editor's back: the
buffer and the disk would then say different things, and whichever was saved
next would win. So an open document is read from its buffer and changed through
it — one replacement of the whole file, so its share of the undo is one entry
and not one per edit the server sent — and then saved, and the server is told.
Everything else is read and written without an editor being made for it, which
is what a rename across five hundred bundles needs.

A workspace edit can also create, move and delete files, which is how renaming a
Java class moves `Foo.java` to `Bar.java`. A file that moves and is open has its
tab closed before the move and reopened under the new name afterwards, or the
next auto-save would put the buffer back at the path the move had just emptied.
The order the server sent its changes in is kept, because it is meaningful:
edits before a move and edits after one both happen, and mean the same thing.

### Scenario: renaming a Java class

- **Given** a Java class in a file of its own, and another file that uses it
- **When** the class is renamed
- **Then** both files say the new name
- **And** the file holding the class has the new name too

### Scenario: a file that is open in two panes

- **Given** a file open in two editor panes and changed by a rename
- **When** the rename is applied
- **Then** both panes show the new text

## ADDED Requirement: A whole rename is one undo

A rename that touched forty files and is undone forty times is not an undo. One
⌘Z takes the whole of it back — every file's text, every file that moved, every
file that went — and the Edit menu names it after the new name so that what it
will take back is legible before it is pressed.

It is on the same stack as what the tree does to files, and that is the only
place it can be: a document's own history knows nothing of the other thirty-nine,
and a rename that moved a file is not a text edit at all.

While a name is being typed, ⌘Z belongs to the field and takes back the typing.

### Scenario: undoing a rename across three files

- **Given** a rename that changed three files
- **When** ⌘Z is pressed once
- **Then** all three say what they said before

### Scenario: undoing a rename that moved a file

- **Given** a rename that moved `Foo.java` to `Bar.java`
- **When** it is undone
- **Then** the file is back under its old name with its old text
