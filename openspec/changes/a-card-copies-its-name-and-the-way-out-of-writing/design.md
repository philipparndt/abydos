## Context

`OpenSpecChange.commands(for:in:)` is the one place that says what a card
offers to copy, per state: Ready offers `/opsx:apply <name>`, In progress three
sentences, Writing, Complete and Archived nothing — Complete has the archive
command through a different door, because it wants the CLI found. A
`CardCommand` has a title the menu shows and a command it copies, and the two
differ on purpose: the pasteboard names the change, the menu does not repeat a
forty-character name three times.

A change knows which artifacts it has (`artifacts: Set<OpenSpecArtifact>`), and
the schema's order is proposal, design, specs, tasks.

## Decisions

**Copy name is one more `CardCommand`, in every state.** Title *Copy name*,
command the change's name. Last in the list, after whatever the state offers,
so the entry that starts work stays first where the eye lands. It is the only
entry whose title and command differ in kind rather than in length, and the
toast says *Copied the change's name*.

**The Writing entry is built from what is missing.** The artifacts not present,
in schema order, become a sentence:

    write the design and the spec delta for <name>, so it is ready to apply

with the labels *the proposal*, *the design*, *the spec delta*, *the tasks*,
joined as prose ("the design and the spec delta"; "the design, the spec delta
and the tasks"). The title is the sentence without the name and the tail, as
the In-progress titles are. A Writing change with nothing missing does not
exist — it would be Ready — so the entry is never empty.

*Ruled out: `/opsx:propose <name>`.* Propose creates a change; it is not what
finishes one. *Ruled out: `/opsx:continue`.* There is no such command in this
project.

*Ruled out: an entry that runs anything.* The board reads a change's state out
of its files and rewrites nothing; both entries copy and stop.

**The verb that prints a card's menu prints the new entries**, and copying
through it puts the text where a run can read it back, so "a Writing card
missing tasks offers *write the tasks*" is a line.

## Risks / Trade-offs

**A menu of five entries on an In-progress card** → three sentences, a
separator, *Copy name*. The separator is what keeps the name from reading as a
fourth sentence.

## Open Questions

None.
