# 447. A profile of this app names another application's code

`sample` and `atos` cannot symbolicate this app as it is normally built. They do
not fail — **they answer, confidently, with somebody else's symbols.**

Found by 0428 while looking for what was burning eight cores. Two profiles came
back naming a *different application's* SwiftUI view types, in a plausible enough
arrangement to be believed and acted on. The finding that mattered was only
identified after rebuilding with `make build PIN_UUID=0`.

## Why

`Scripts/pin-uuid.py` pins a fixed build UUID into the binary, deliberately —
every build then has the same one. The system symbol server caches by UUID and
answers for whichever binary first claimed it, which is not necessarily this
one, and never the one you just built.

So the mechanism that makes builds reproducible makes them unprofilable, and the
failure is silent. A tool that said "no symbols" would cost a minute; one that
answers with the wrong names costs however long it takes to notice that the
functions do not exist in this repository.

## Why this matters more than it looks

Performance work here is measurement-led on purpose — 0435, 0437 and 0428 were
all settled by numbers rather than by reading — and this quietly poisons the
first tool anybody reaches for. 0446 is the next piece of performance work and it
starts by profiling exactly this app.

## Worth deciding rather than assuming

- **Whether the pin is needed at all for a local build.** It exists so a release
  can be matched to its crash reports; a debug build somebody is profiling has no
  such need, and `PIN_UUID=0` already exists as the escape hatch.
- **Whether `make dev` and `make run` should stop pinning**, leaving `build` and
  `release` as they are. That would make the default development build
  profilable and leave the reproducible one alone.
- **Whether the tools can be made to say so.** If a stale UUID can be detected —
  comparing what `atos` answers against a symbol known to be in this binary —
  then a line in `make perf`, or in the profiling instructions, is worth more
  than a change in behaviour.

Not investigated: whether `dsymutil`, a fresh `dSYM`, or clearing the symbol
cache is enough to make a pinned build symbolicate honestly.

## Reproduced

One build, one address, changing nothing but the sixteen bytes of `LC_UUID`.
`make build CONFIG=debug` and then the same thing again with `PIN_UUID=0`; the
compiler never ran a second time, so the two bundles differ in the UUID and in
the signature that had to be redone over it, and in nothing else at all.

    $ nm -n build/Abydos.app/Contents/MacOS/Abydos | grep ' _main$'
    0000000100001f60 T _main

    $ atos -o build/Abydos.app/Contents/MacOS/Abydos -arch arm64 0x100001f60
    ts_lex (in Abydos) (parser.c:1617)          # uuid C94373A9…, the pin
    main (in Abydos) (main.swift:0)             # uuid BC3C7493…, the linker's own

The binary's own symbol table and `atos` disagree about the same address in the
same file. That is the whole fault, and it takes two commands to see.

### The two profiles

Both are `sample <pid> 5` over the same debug bundle, launched the same way on
the same project, seconds apart. The top of the main thread first — the frame
directly beneath `start` in dyld, which can only ever be `main`:

    pinned      3454 start  (in dyld) + 6688
                3454 ts_lex  (in Abydos) + 300  [0x102092004]  parser.c:0

    unpinned    3600 start  (in dyld) + 6688
                3554 main  (in Abydos) + 164  [0x100a5a004]  main.swift:12

And the heaviest frames each profile attributes to this app, in order:

    pinned                                    unpinned
    ------------------------------------      ------------------------------------
    static GitTags.describe(_:in:)            main
    DockedPane.build()                        closure #2 in StallWatch.start(…)
    ts_lex                                    closure #1 in PseudoTerminal.watchForExit(pid:)
    CommandInfoV0.__derived_struct_equals      AppDelegate.applicationDidFinishLaunching(_:)
    EditorViewController.measureTypingForTesting(presses:)

The right-hand column is an app starting up. The left-hand column is fiction:
371 samples inside `measureTypingForTesting` in a run where nobody typed and no
test was running, and `GitTags.describe` at the very root of the main thread.

The reason 0428 believed it is visible in the deeper frames. A second sample of
the same pinned build, taken while it sat idle, does not print rubbish; it
prints this, with source files and line numbers:

    31 CodeView.insertNewlineWithIndent()          <stdin>:0
    31 static LineIndent.outdent(_:tabWidth:)      LineIndent.swift:31
    31 TextDocument.replace(utf16Range:with:caretBefore:)
    31 CodeView.moveToLineEdge(start:extending:)   CodeView.swift:2094
    31 CodeView.dedentIfClosingBrace(_:)           CodeView.swift:2168
    31 CodeView.paste(_:)                          CodeView.swift:2521
    31 CodeView.setMarkedText(_:selectedRange:replacementRange:)  CodeView.swift:2565
    15 closure #5 in DiagramExportCommand.run(…)   DiagramExportCommand.swift:113
    11 EditorTabBar.init(frame:)                   EditorTabBar.swift:99

Every one of those functions exists in this repository, at that line. None of
them called the next one, and none of them ran. Under `-[NSViewBackingLayer
display]` the pinned profile has nothing but offsets into `ts_parse_table`, a
*data* symbol; the unpinned profile has a drawing path that reads the way one
should — `PanelTabStrip.draw` into `drawGlyph` into `Theme.symbol` into
`-[NSImage imageWithSymbolConfiguration:]`.

That is why this is worse than "no symbols". The wrong answer is made of this
project's own vocabulary, so nothing about it looks foreign; 0428 described what
it saw as another application's view types, and it was not even that.

`images/startup-pinned.txt` and `images/startup-unpinned.txt` are the first 150
lines of each report.

### It is not a stale build, and `-o` does not help

Worth stating because both are the obvious first guesses and both are wrong.

The installed app was written at 17:46:26 and the process sampled was launched
at 17:46:30 from that same file — `atos` was reading exactly the binary that was
running, and still answered `ts_lex` where the file's own symbol table says
`_main + 100`. Naming the file explicitly with `-o` does not help either:
CoreSymbolication takes the UUID *out of* the file it was handed, asks the system
whose symbols those are, and prefers that answer to the file. Nine binaries on
this machine carry `C94373A9-FCB2-3966-B045-208B26A4CA30` — every worktree's
`build/Abydos.app`, the installed copy, and a `build/ideai.app` under the old
name — and all nine, asked about the same address, return the identical wrong
answer. Copy one to `/private/tmp`, change only the UUID, and it becomes right;
change it back, and it is wrong again.

## What was decided

**Every build that pins today still pins.** This is the opposite of what the
entry above proposed, and the entry had the reason for the pin the wrong way
round. It is not there for reproducibility or for crash reports — `Scripts/
bundle.sh` and `Scripts/release.sh` both say so, and a release is the one build
that turns it *off*, precisely so its crash reports stay unambiguous. The pin is
there because macOS files the Local Network grant against the executable's UUID,
a rebuild loses it, and on macOS 27 beta nehelper refuses UserEventAgent the
connection that would present the prompt, so no new grant can be made at all.
The denial is inherited by everything the app launches: a debugger, a program
under test.

Which means `make dev` and `make run` — the entry's candidates for un-pinning —
are the *worst* two to un-pin. They are what somebody debugs with. Trading a
profiler that lies for a LAN that is silently unreachable is the same shape of
fault moved somewhere less visible, and it would be paid by every session rather
than by the occasional one that profiles.

So the change is an entry point instead of a default:

- **`make profile`** builds release with `PIN_UUID=0` and then proves the result
  symbolicates as itself. Release as well as unpinned, because a profile of a
  debug build is a profile of a different program — the trap 0416 found in the
  performance suite — and because that is what 0446 actually did by hand.
- **`Scripts/symbol-check.sh`**, also `make symbol-check`, is the detector, and
  the answer to the third question above: yes, the wrong answer can be made
  loud, cheaply and without heuristics. Take the address the binary's own symbol
  table gives for `main`, ask `atos`, and refuse to be quiet if the answer is
  anything else. `main` rather than one of ours because every executable has it,
  no library can shadow it, and it survives a rename.
- **`Scripts/bundle.sh`** prints one line every time it pins, since that is the
  only moment anybody watches this happen.
- **`Scripts/pin-uuid.py`** now carries the measurement above in its docstring.
  It is where somebody wondering why builds are pinned will look, so it is where
  what pinning costs has to be written down.

Not `make perf`, which the entry suggested: `perf` and `scale` run a test binary
SwiftPM links and nothing pins that. Only the `.app` is affected. Said in the
Makefile and the README so the next person does not go looking.

## Ruled out

- **Un-pinning `make dev` and `make run`.** Argued above. The pin is not about
  reproducibility, and those two are where the grant matters most. Not re-tested
  today: nobody proved *this week* that an unpinned build still loses the LAN —
  it is taken from what `Scripts/bundle.sh` records, which is somebody else's
  measurement paid for at the time.
- **A stale binary on disk, and `atos -o`.** Both above.
- **`dsymutil` and a fresh `dSYM`, which the entry left open.** The answer is
  *not reliably*. `dsymutil` on a pinned binary takes 3 s and produces a `.dSYM`
  carrying the same pinned UUID; `atos -o <the dSYM's own DWARF>` then answers
  correctly. But a `.dSYM` merely sitting beside the binary is not enough: in one
  arrangement (a copy under `/private/tmp`) it won and `atos -o <binary>` became
  right, and in another (the same binary inside `build/Abydos.app`) it lost and
  `atos` and `sample` both went on printing `ts_lex`. What decides it was not
  identified. Worse, making one is actively antisocial — the new `.dSYM` is a
  further claimant to the same UUID, so it can go on to answer for somebody
  else's build, and it lands inside the bundle where it breaks the signature.
  `PIN_UUID=0` costs nothing and is not conditional.
- **Clearing the symbol cache.** There is nothing found to clear. There is no
  `com.apple.DebugSymbols` preference domain on this machine,
  `/System/Library/Caches/com.apple.coresymbolicationd` is empty, `mdfind` over
  `com_apple_xcode_dsym_uuids` does not know this UUID, and `atos` writes nothing
  under any cache directory while answering. Pinning a *fresh* UUID onto two
  different binaries in turn does not make the second inherit the first's
  answers, so this is not a cache `atos` fills as it goes — something registered
  `C94373A9` durably, before today, and which of the nine claimants wins was not
  established. It does not change what to do about it.
- **Naming the culprit.** Tried and abandoned. It is the wrong question: the
  point of the pin is that there is no unique owner, so the answer would be true
  of this machine this week and of nothing else.
- **`sudo fs_usage` and the unified log** as ways to watch the lookup happen.
  `fs_usage` needs root, and a `log stream` filtered on `DebugSymbols` and
  `CoreSymbolication` produced not one line while `atos` answered wrongly.

## Steps

- [x] Reproduce: profile a pinned build and an unpinned one, and show the two
      answers side by side in this entry
- [x] Decide which builds pin, and say why in `Scripts/pin-uuid.py` itself
- [x] Make the wrong answer loud, if it can be detected at all
- [x] Say where somebody profiling this app should start, where they will look
- [x] Write down here what was ruled out on the way
- [x] `spec/<capability>.md` says what the project now does, if anything a user
      sees changed — it may not, and then say so

No spec delta. Nothing a user of the app sees changed: this is entirely the
build and its command line, and `spec/` covers what the program does for
somebody using it, not how it is made. The README's new *Profiling* section and
`make help` are where a developer finds this.
