## 1. Asking

- [x] 1.1 `textDocument/codeAction` for the selection, carrying the diagnostics
      under it in the request's context.
- [x] 1.2 The answer parsed into something the editor can show: title, kind, and
      whether it arrived with an edit.
- [x] 1.3 Tests over the parsing, including an action that is a command and one
      with no edit at all.

## 2. Taking

- [ ] 2.1 `codeAction/resolve` for an action that arrived without an edit, before
      anything is applied.
- [ ] 2.2 The edit goes through 0453's applying — the rope for open documents,
      disk for closed ones, one undo — and not a second implementation.
- [ ] 2.3 An action carrying a command goes through `workspace/executeCommand`.

## 3. The request coming the other way

- [x] 3.1 `workspace/applyEdit` handled as an inbound request: apply through the
      same machinery and answer whether it was applied.
- [x] 3.2 A refusal is answered honestly rather than optimistically, and says
      what happened.
- [x] 3.3 A test with a server that asks for an edit this app cannot apply.

## 4. Seeing that there is anything

- [ ] 4.1 **Measure before choosing**: how often jdtls, sourcekit-lsp and
      kmp-lsp return a non-empty list for an ordinary caret position in a real
      file. A mark on every line is the outcome to avoid.
- [ ] 4.2 Decide where the offer lives — on the diagnostic, in the gutter, or
      only on a keystroke — and write down what lost.
- [ ] 4.3 A keystroke that always works, whatever else is decided.
- [ ] 4.4 `source.*` actions, which have no cursor, are reachable somewhere that
      is not a menu at the caret.

## 5. Which server answered

- [ ] 5.1 kmp-lsp's list is syntactic and short; jdtls's is not. Somebody can
      tell which they are getting.

## 6. Watched

- [ ] 6.1 Against a scratchpad copy, never a real checkout: a Java file with a
      missing import, the offer taken, the import added.
- [ ] 6.2 An action that resolves lazily, taken.
- [ ] 6.3 An action that is a command, taken, with the server's own
      `applyEdit` arriving and being answered.
- [ ] 6.4 A file with nothing on offer, showing nothing.

## 7. Finish

- [ ] 7.1 `.abydos/backlog/spec/language-servers.md` says what a server offers
      and what happens to each kind of offer. Name any sentence this makes
      untrue.
- [ ] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [ ] 7.3 Write down what was ruled out on the way.
