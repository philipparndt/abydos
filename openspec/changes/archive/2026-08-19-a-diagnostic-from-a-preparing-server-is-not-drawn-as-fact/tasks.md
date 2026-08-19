## 1. What weight to draw at, decided where it can be tested

- [x] 1.1 A function in `AbydosKit` answering, for a severity and whether the
      server is preparing, which role a diagnostic is drawn in.
- [x] 1.2 Named as claims: `anErrorFromAPreparingServerIsDrawnQuietly`,
      `anErrorFromAReadyServerIsDrawnAsAnError`, and the same pair for a warning.
- [x] 1.3 A hint or an information diagnostic is unchanged either way — it is
      already drawn in the quiet weight, and preparing must not make it louder.

## 2. Where the colour comes from

- [x] 2.1 Decide between moving the two diagnostic severities into the scheme
      files, as 0536 did for the find highlights, and deriving the provisional
      weight from a role that is already there. **A third hardcoded hex in
      `CodeView.color(for:)` is the outcome to avoid.**
- [x] 2.2 Whichever way, check both lightnesses on a real file: a dim that reads
      as "not important" on the amber ground and as "disabled" on paper is two
      different sentences.
- [x] 2.3 If the severities move into the scheme, every shipped scheme gains the
      keys and `SchemeTests` covers them, since a missing key refuses the file.

## 3. Telling the editor

- [x] 3.1 `CodeView.setDiagnostics` learns whether what it is being given is
      provisional, and redraws when that changes with the same diagnostics —
      today it returns early when the grouping is unchanged, which is exactly the
      case the end of preparation hits.
- [x] 3.2 `EditorViewController` asks `LanguageService.isPreparing` for the file's
      project and language on the path diagnostics already take.
- [x] 3.3 `LanguageService` says when a server stops preparing, not only when a
      diagnostic arrives. Preparation ends with a progress token closing and
      nothing else, and a view waiting for the next diagnostic would hold a dim
      error on screen after the server was ready.

## 4. Watching it, on a cold package

- [x] 4.1 `abydos-examples/cadova-models` with `.build` deleted, opened by the
      driver, photographed at t+20 s: the diagnostic present, dimmed, the chip
      saying preparing.
- [x] 4.2 The same package photographed after preparation, with a real mistake
      typed into it: red, in the ordinary colour, no trace of the state.
- [x] 4.3 A second open with everything built: ordinary colours from the first
      frame, since a warm start is 1.2 s of preparation and must not flicker.
- [x] 4.4 Both pictures in the item, the way 0501 kept its before and after.
      Photographed in the scratchpad: the cold open with the diagnostic dimmed
      (0 pixels of error red anywhere in the editor) and the same package once
      the server was ready (106). Said in words as well, by `--diagnostics`,
      which is the report this needed — the state changes a minute after the
      file opens and nothing else on screen moves with it:

          at 25s   server preparing: true
                     1: error drawn as quiet — No such module 'Cadova'
          at 140s  server preparing: false
                     6: error drawn as error — Cannot convert value of type…

## 5. Finishing

- [x] 5.1 `make test`, and `make warnings` — a separate verb, run before this is
      finished.
- [x] 5.2 The spec delta folded into `.abydos/backlog/spec/language-servers.md`
      as well, since that file is the account that stays.
