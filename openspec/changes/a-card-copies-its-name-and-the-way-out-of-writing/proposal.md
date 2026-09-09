## Why

The maintainer, 2026-09-09, two asks about the cards on the OpenSpec board:

- *"It should be possible to copy the openspec id for every card in all
  states."* A change's name — `the-light-terminal-can-be-read` — is what every
  command and every sentence about it takes, and the card shows it but does
  not hand it over. Copying it today means selecting text in a card title, or
  reading it off and typing forty characters.
- *"There should be a copy action to bring the task from writing to ready."* A
  card in Ready offers `/opsx:apply <name>` to copy; one part-way through
  offers three sentences; one that is Complete offers `openspec archive
  <name>`. A card in Writing offers nothing — deliberately, because it cannot
  be applied and the CLI says so. But it can be *finished*, and the card knows
  exactly what is missing: OpenSpec answers `blocked` for apply and names the
  artifact it waits for, and the card says which. The one column where the
  next step is clearest is the one with no entry for it.

Both are the card's menu, built in one place per state in `OpenSpecChange`,
and both are copy actions rather than actions on the change: the board reads a
change's state out of its files and rewrites nothing, and these keep that.

There is no `/opsx:continue` in this project — its commands are apply, archive,
explore, onboard, propose and sync — so the way out of Writing is what the
In-progress column already does for its judgement calls: a sentence a person
pastes into an assistant, which names the change and what it still lacks.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-09-09.

## What Changes

- **Every card copies its name.** One entry, on every card in every column
  including Archived, that puts the change's name on the pasteboard and says
  so in the toast the other copies use. The entry reads *Copy name*; what it
  copies is the name alone, no path, no slash command.
- **A card in Writing offers the way to Ready.** A sentence, to copy, that
  names the change and the artifacts OpenSpec says are missing, in the order
  the schema wants them written:

      write the design and the spec delta for <name>, so it is ready to apply

  The words come from what `openspec instructions apply --change <name>` reports
  as blocking — which the card already reads to draw its column — so a change
  missing only tasks says *write the tasks for <name>*. As with the In-progress
  sentences, the entry shows the sentence without the name and copies it with.
- **Nothing moves a card.** Copying is all either entry does; the card follows
  the files when the documents are written, as the board's rule says.

## Capabilities

### Modified Capabilities

- `openspec-board`: what a card offers to copy — its name in every state, and
  in Writing the sentence that finishes it.

## Impact

- **AbydosKit**: `OpenSpecChange`'s per-state card commands gain the name entry
  everywhere and a Writing entry built from the blocking artifacts.
- **AbydosApp**: the card menu shows them; the existing copy-and-toast path
  carries them.
- **Driver**: the verb that prints a card's menu, so a run can say what a
  Writing card offers and what a copy put on the pasteboard.
