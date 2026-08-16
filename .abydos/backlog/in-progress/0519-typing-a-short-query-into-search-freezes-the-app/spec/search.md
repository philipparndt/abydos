<!-- What this item changes about `search`. Folded into
     .abydos/backlog/spec/search.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       Search results can be marked done, several at a time
       Marking done is never a deletion, and ⌘⌫ is never the key for it
       A mark survives the search being run again
       Marks are hidden on request, so the list can also empty
       ⌘Z in the results list takes back the last marking
       The results list can be worked from the keyboard
       Search results go wherever a usages list goes
-->

## ADDED Requirement: The window goes on answering while a broad search runs

Results stream into the list as the walk finds them, and a batch that arrives
costs what that batch holds. Nothing about it is proportional to what has
already been found: the rows for a file are built once, when the file arrives,
and so are the marks its ticks are keyed on. Rebuilding the whole list happens
only for the reasons that change the whole list — a row ticked, ⌘Z, a file
folded shut, the hide-done toggle — and never because more results came in.

A two-character query over a project of any size is an ordinary thing to type
on the way to a longer one, and the window keeps drawing, scrolling and taking
keys throughout.

### Scenario: two characters, and then two more

- **Given** a project large enough that the query matches tens of thousands of
  times
- **When** two characters are typed into the search field, and then the query is
  changed again while the walk is still running
- **Then** the window answers throughout, and each further batch costs what that
  batch holds rather than what the list already holds

### Scenario: the ticks are unmoved by the streaming

- **Given** a search still running, with some of the rows already marked done
- **When** more results arrive
- **Then** the marks stay where they are, and the count of what is done is still
  right

## ADDED Requirement: A list that is not the whole answer says so

Both the number of files and the number of matches are bounded, and the bounds
stop the walk rather than hiding what it found: past them the remaining files
are not read. A one-character query is a request for a row per line of the
project, and no list is worth building at that size.

When a bound has been reached the status line says so, in the same breath as
the count and in front of it: **the first 20018 in 27 files · more not shown**.
A search that fits inside the bounds says nothing about them and reads as it
always has.

Which of the two bounds stopped the walk is not distinguished, because the
answer to both is the same one: the query is too broad, and the way to see the
rest is to narrow it.

### Scenario: a query that matches most of the project

- **Given** a project with far more matches than the list will hold
- **When** the search is run
- **Then** the list holds the first of them, whole file by whole file, and the
  status line says the count it is showing and that more was not shown

### Scenario: an ordinary search

- **Given** a query matching ten times in four files
- **When** the search is run
- **Then** the status line reads `10 in 4 files` and says nothing about caps
