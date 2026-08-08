# Add the branches and structure views

`e428bbdf2` · 2026-07-31

The two remaining strip buttons were disabled placeholders. The sidebar
now hosts four tool windows rather than two, switched as tabs, with ⌘1
to ⌘4.

Branches lists local branches, each remote's, and tags, with the current
one ticked and ahead/behind counts beside the ones that track something
— which is the reason to look at the list at all when deciding to push
or pull. Checkout, branch-from-here, merge and delete are on the context
menu; a filter field is at the top because the case worth supporting is
a repository with more branches than fit on screen. Checking out a
remote-tracking branch creates the local branch that tracks it rather
than detaching HEAD, which is what anyone means by it. Branch names are
validated before git runs, so a bad one is a sentence rather than git's
message about ref formats.

Structure outlines the open file from the grammar's own tags query, and
follows the front tab. Three things had to be got right for it to be
readable:

- Position comes from the *name* capture, not the definition. Several
  grammars — Swift's among them — hang `@definition.method` on the
  enclosing type, so every member reported the type's line.
- Only a container adopts children. Those same grammars capture a type
  and all of its members against one declaration range, and treating any
  enclosing range as a parent chained the members into each other, one
  property nested inside the last all the way down.
- Locals are dropped. A `let` inside a function body is captured exactly
  like a member, so the tree is what tells them apart; without this the
  outline listed every temporary in every function.
