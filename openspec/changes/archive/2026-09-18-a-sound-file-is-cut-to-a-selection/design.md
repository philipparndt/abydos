## Context

A sound tab (`AudioFileView`) plays a file through `AudioPlayback`, draws it
with `AudioCanvas` from `AudioAnalysis`, and had no edited state: no
document, no dot, nothing for ⌘S. The hex editor is the one other tab that is
edited without a `TextDocument`, and the tab asks it for `isDirty` and
`save()`.

## Goals / Non-Goals

**Goals:** `i`/`o` marks; keep and delete; undo and redo; ⌘S in the file's own
format; the close prompt; an MP3 refused in words.

**Non-Goals:** selecting by dragging (a drag scrubs, and scrubbing is what the
canvas is for); fades or crossfades at a join; a loop over the selection;
saving an MP3 as another format.

## Decisions

### 1. Working copies, not an edit list

Each cut renders what it leaves of the current source into a 32-bit float CAF
in `$TMPDIR/abydos-audio-edits/`, and the tab plays and draws that file. Undo
and redo are stacks of those files, with nil standing for the file itself.
*Ruled out: a list of kept ranges over the original, played and drawn as
one.* `AudioPlayback` and `AudioAnalysis` take a URL and are proven on files;
teaching both to compose ranges is a second player and a second reader for
one feature. A copy costs disk for the length of the session, and the tab's
close deletes them.

### 2. Float CAF between cuts, the file's format only at ⌘S

A chain of cuts on an `.m4a` decodes it once and encodes it once. *Ruled out:
writing each cut in the original format* — each would be another generation
of AAC.

### 3. Exact to the frame, no fades

Marks become frames by truncation, once, in `AudioCut.frames`. A loop cut on
its downbeat is the use that was asked for, and a fade added silently is a
loop that no longer loops. A click at a careless join is the cut somebody
made.

### 4. The file is replaced whole

⌘S writes a sibling with a hidden name and `replaceItemAt`s the original, so
a failed encode leaves the file as it was. The writer is created and released
inside one function: `AVAudioFile` finishes a file when released, `close()` is
macOS 15, and a writer alive at the rename is a header that says nothing was
written.

### 5. Keys, and what the Edit menu offers

`i`, `o`, `k`, `⌫` and Escape in `keyDown`, only while the tab has the
keyboard. `undo:` and `redo:` are answered by the view, as the checklist and
the tree answer them, and `responds(to:)` says no while a stack is empty so
the menu item greys rather than doing nothing.

## Driven proof

`--audio-steps` on synthesised files under the scratchpad, 2026-09-14: an
eight-second 16-bit stereo WAV and an AAC `.m4a` made from it by `afconvert`.

| Steps on `take.wav` | Report |
| --- | --- |
| `seek:2,in,seek:4,out` | `selection=88200..<176400 label="selected 0:02.000" buttons=shown` |
| `keep` | `frames=88200 duration=2.000 dirty=true undo=1 source=working copy`, 1 411 244 bytes on disk — unchanged |
| `undo` | `frames=352800 dirty=false redo=1 source=file` |
| `redo` | `frames=88200 dirty=true` |
| `seek:0.5,in,seek:1,out,delete` | `frames=66150 duration=1.500 undo=2` |
| `save` | `written`, `dirty=false`, 268 696 bytes; `afinfo`: 1.500000 s |

On `clip.m4a`, `seek:1,in,seek:3,out,keep,save` wrote an AAC file of 2.000 s.
Afterwards the directory held only the two files — no hidden sibling — and
`abydos-audio-edits` held no working copy.

The unit tests prove the join: the frame after a deleted 3 s–3.5 s stretch
is the frame that was at 3.5 s, and a 16-bit WAV, a 24-bit AIFF and a float
CAF are each written back at their own depth and rate.

## Risks / Trade-offs

- [⌘S on a long file runs on the main thread] → an eight-minute AAC encode is
  seconds of beach ball; moving it off is the next step if it is felt.
- [A working copy of an hour of stereo is 1.3 GB] → deleted with the tab; a
  cut chain on such a file is disk the length of the session.
