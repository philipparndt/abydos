## Context

`CodeView.doCommand(by:)` is a switch over the selectors AppKit sends a text
view, ending in `default: break` with a comment saying that staying quiet is
right. It is: `noop:`, `complete:`, `cancelOperation:` and a long tail arrive
there in the ordinary course of typing.

The three bugs this is about were all the same shape. A key moved the caret
without Shift and did nothing with it, because the `…AndModifySelection:` twin
was missing from the switch. Nothing said so; somebody read the switch.

The count that bounds the noise, reproduced against the SDK rather than
remembered:

    H=$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/AppKit.framework/Headers/NSResponder.h
    grep -o '\- *(void)\(move\|select\)[a-zA-Z]*:' "$H" | sed 's/.*)//;s/:$//' | sort -u

43 declared, 29 handled, 14 possible lines.

## Goals / Non-Goals

**Goals:**

- A key that does nothing names the selector nobody handled, once.
- Nothing is said in a release build, and that is checked rather than assumed.
- Nothing is said about selectors outside the `move`/`select` families.

**Non-Goals:**

- Handling any of the 14. This says what is missing; taking one is its own item.
- Finding bugs nobody triggers. Nothing prints until a key is pressed.
- Changing what a release build does in any way.

## Decisions

**The two families, and nothing else.** The value here is the ceiling: 14 lines
for the life of a debug build. `default:` as a whole has no such bound, which is
what the existing comment is refusing and what makes this different from
refusing it.

**Once per selector, for the life of the process.** A held key repeats, and a
line per repeat is the same noise this is trying not to be. A set of names
already said is the whole mechanism.

**Through whatever this project already logs with, not `print`.** A bare `print`
in a view is a thing nobody can turn off and nothing can capture; the driven runs
already read this app's log. Which one it is belongs to the work — the item says
so, and it is a question about what exists rather than about what to do.

**Debug builds only, decided at compile time.** `#if DEBUG` rather than a
setting: a setting is a thing to be found and turned on by somebody who already
knows what they are looking for, which is the opposite of the point.

## Risks / Trade-offs

- **A name printed for a selector that is deliberately unhandled** — a motion
  this editor has decided not to have. → It is still true that nothing handled
  it, and 14 is small enough that a known-and-declined list would cost more to
  keep than to read.
- **It only helps somebody running a debug build.** → That is where the drivers
  run, which is where editor items are worked.

## Open Questions

- **Does this earn a requirement in `spec/editor.md`?** It is what a debug build
  says about itself rather than what the editor does. The item says it may well
  not, and asks for the answer to be written down either way.
- **⌃B and ⌃F do nothing** — found during 0495, one of the 14, half-implemented
  emacs bindings nobody has asked for. Not part of this; named because it is the
  kind of thing this exists to surface.
