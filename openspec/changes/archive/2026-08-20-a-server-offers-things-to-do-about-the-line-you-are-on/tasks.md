## 1. Asking

- [x] 1.1 `textDocument/codeAction` for the selection, carrying the diagnostics
      under it in the request's context.
- [x] 1.2 The answer parsed into something the editor can show: title, kind, and
      whether it arrived with an edit.
- [x] 1.3 Tests over the parsing, including an action that is a command and one
      with no edit at all.

## 2. Taking

- [x] 2.1 `codeAction/resolve` for an action that arrived without an edit, before
      anything is applied.
- [x] 2.2 The edit goes through 0453's applying — the rope for open documents,
      disk for closed ones, one undo — and not a second implementation.
- [x] 2.3 An action carrying a command goes through `workspace/executeCommand`.

## 3. The request coming the other way

- [x] 3.1 `workspace/applyEdit` handled as an inbound request: apply through the
      same machinery and answer whether it was applied.
- [x] 3.2 A refusal is answered honestly rather than optimistically, and says
      what happened.
- [x] 3.3 A test with a server that asks for an edit this app cannot apply.

## 4. Seeing that there is anything

- [x] 4.1 **Measured**, in `CodeActionLiveTests`, which asks at the first
      non-space character of every line of a real file — an ordinary caret
      position — and counts. Load 14-25 over 10 cores.

      - **gopls: 16 of 16 lines (100%)** offer something. Kinds:
        `source.organizeImports`, `source.doc`, `source.splitPackage`,
        `source.toggleCompilerOptDetails` and `gopls.doc.features` on every
        line, `source.addTest` and `source.assembly` on eleven,
        `refactor.rewrite.changeQuote` on two. 86 of them are commands rather
        than edits.
      - **jdtls: 10 of 10 lines (100%)** offer something, 9 of 10 excluding
        `source.*`. 37 `quickfix`, 12 `quickassist`, `source.generate.accessors`
        and `source.organizeImports` on every line. **81 of the 83 arrived with
        no edit in them** — jdtls resolves, and answering a list cheaply is the
        normal case rather than the corner one.
      - **sourcekit-lsp and kmp-lsp: not measured.** kmp-lsp is not installed on
        this machine and is reachable only through its container image, and the
        container runtime is down. Two servers of different kinds agreeing on
        100% is enough to decide this, and the decision does not get worse if a
        third offers less.

      **The number to keep**: a list is non-empty essentially always, and
      filtering out the kinds that are about the file does not save it —
      gopls's `gopls.doc.features` is a vendor kind outside the protocol's
      hierarchy and comes back on every line too.
- [x] 4.2 **Decided: a keystroke, and a mark only where there is a diagnostic.**

      A gutter indicator driven by "does this line have actions" would be on
      every line of every file, which is the outcome 4.1 existed to rule out —
      and it is ruled out by measurement rather than by taste. What lost:

      - **A gutter mark per line.** 100% of lines, both servers. Dead on
        arrival.
      - **A mark filtered to non-`source` kinds.** Still 100% for gopls, 90%
        for jdtls. A client cannot filter its way out of this, because a server
        may invent kinds.
      - **Asking on every caret move to decide whether to draw anything.** One
        request per position, against servers that take tens of milliseconds to
        seconds — the cost of an indicator nobody can read anyway.

      What is left is the keystroke, which always works and asks only when
      somebody asks, and the diagnostic — which is drawn already, is drawn only
      where something is wrong, and is where somebody is already looking when
      they want a fix. That answers the open question about the diagnostic's own
      sentence: yes, and it is the only always-on affordance this measurement
      leaves standing.
- [x] 4.3 A keystroke that always works — ⌥⏎, IDEA's, as a menu item so that
      the key equivalent is matched before the text view turns it into a
      newline. Nothing else, whatever else is decided.
- [x] 4.4 `source.*` actions, which have no cursor, are reachable somewhere that
      is not a menu at the caret: Edit ▸ Source Actions…, asked with
      `only: ["source"]` and filtered to source kinds, so the caret's own menu
      never shows them.

## 5. Which server answered

- [x] 5.1 kmp-lsp's list is syntactic and short; jdtls's is not. Somebody can
      tell which they are getting.

## 6. Watched

- [x] 6.1 Against a scratchpad copy, never a real checkout: a Java file with a
      missing import, the offer taken, the import added. Driven through the
      gesture's own path with `--code-actions 4 90 --code-action-take "Import
      'List' (java.util)"`, load 9.4 over 10 cores. jdtls offered eight ways to
      read the line — `Import 'List' (java.util)` among `java.awt`,
      `com.sun.tools.javac.util`, `Create class 'List<T>'` — and the file
      afterwards began `package com.example.fix;` / `import java.util.List;`.
- [x] 6.2 An action that resolves lazily, taken — and it is not a corner case:
      **22 of 22** of jdtls's offers at that line arrived with no edit in them.
      The one that was taken was resolved on the way, which is the only reason
      an import appeared.
- [x] 6.3 An action that is a command, taken, with the server's own `applyEdit`
      arriving and being answered. jdtls resolved its `Organize imports` into a
      plain edit, so the whole loop was watched against gopls instead, whose
      offers are commands: `Extract declarations to new file` →
      `workspace/executeCommand` → **`ACTIONS edits the server asked for: 1`** →
      `greeting.go` created beside a `shelf.go` cut down to its package clause.
      A file created by a server's own request, through the applier a rename
      uses.
- [x] 6.4 A file with nothing on offer, showing nothing — and saying so:
      openscad-lsp answers nothing at all, and the gesture said "Nothing on
      offer here — openscad-lsp offers nothing about this line."

      **Worth writing down: the empty case is rare.** gopls returns `Browse
      gopls feature documentation` for every position in every file tried,
      including blank lines and comments, so with that server the sentence can
      never appear. It took a third server to see it.

## 7. Finish

- [x] 7.1 The `language-servers` capability says what a server offers and what
      happens to each kind of offer. `.abydos/backlog/spec/language-servers.md`
      no longer exists — the backlog was dropped, and `openspec/specs` is the
      one copy.

      **The sentence this makes untrue** is in the requirement next door: *A
      server can change the code, and rename is what it is asked for.* Rename
      was the first thing asked of a server that changes files and is no longer
      the only one. The delta carries a `## MODIFIED Requirements` section
      saying so and pointing at the new requirement, rather than leaving two
      requirements in one capability disagreeing about what a server is asked.
- [x] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
      `make test exit=0` — 3052 tests in 401 suites, 2 known issues, load 9.6
      over 10 cores. `make warnings exit=0`, four warnings and all four in
      vendored tree-sitter C.

      One earlier `make warnings` in this session exited 1; three runs after it,
      over the same sources, exited 0 with the same four vendored warnings, and
      nothing between them touched a Swift file. It is not explained. It is the
      shape `.abydos/today.md` already records for `make test` — a target
      failure that did not reproduce in five runs — and it is written here
      rather than left out, because a red run nobody mentions is how a real one
      gets ignored later.
- [x] 7.3 What was ruled out on the way:

      - **A gutter mark, and a filtered gutter mark.** Ruled out by 4.1's
        measurement rather than by taste: 100% of lines, both servers, and 100%
        again for gopls with `source.*` removed.
      - **Asking on every caret move** so that something could be drawn only
        where there is anything. One request per position against servers that
        take tens of milliseconds to seconds, to feed an indicator that would
        be on anyway.
      - **Treating an action with no edit as an empty edit.** The obvious first
        bug, and the measurement says how obvious: 22 of 22 of jdtls's offers
        at one line arrived empty. It would have been a menu that works and
        does nothing.
      - **A second way to apply a `WorkspaceEdit`.** The server's own edit goes
        through the same plan, the same applier and the same single undo entry a
        rename uses, including when it arrives as `workspace/applyEdit`.
      - **Answering `applyEdit` optimistically.** A `true` this app cannot back
        up teaches the server that a file says something it does not. The
        refusals answer `false` with what happened, and `halfDone` names the
        files left changed.
      - **Editing or sorting what a server offers.** Whatever it sends is what
        the menu says, in its own words, the way rename already works — including
        `Import 'List' (com.sun.tools.javac.util)`, which is rarely what anybody
        wants and is jdtls's to rank.
      - **Deciding for the server which actions are worth showing.** The one
        rule applied is positional: `source.*` is about the file and is asked
        for, and shown, somewhere that is not a menu at the caret.
      - **kmp-lsp, as a third measurement.** Not installed on this machine and
        reachable only through its container image, with the container runtime
        down. Two servers of different kinds agreeing on 100% decides this; a
        third offering less would not undecide it.
