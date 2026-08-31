## 1. The kind (AbydosKit)

- [x] 1.1 `FilePreview.Kind.video` for `mp4`, `mov`, `m4v`, with `defaultMode` and `hasPreview` answering the way `image` does
- [x] 1.2 Kind tests beside the existing ones: the three containers are video, `webm` and `mkv` are not, and a `.mov` inside a path with dots stays one

## 2. The player (AbydosApp)

- [x] 2.1 `VideoFileView` wrapping `AVPlayerView`: asset loaded, first frame shown, paused, inline controls; error state left to the player view
- [x] 2.2 `makeVideoTab` beside `makeImageTab` (document nil, previewMode `.preview`) and the one new case in the open dispatch
- [x] 2.3 Pause when the tab leaves the front, keep the position, never resume by itself; teardown releases the player with the tab
- [x] 2.4 External changes follow `ImageFileView`'s precedent — which turned out to be: loaded at open, nothing watches. The player streams what the file held when opened; matching the picture's behaviour is no code

## 3. Proving it

- [x] 3.1 `--video-report` prints the front tab's player state; the driven open answered `video demo.mp4 paused duration=1.0s`
- [x] 3.2 Driven open of a generated one-second clip: report says paused with the duration. The screenshot shows the tab, chrome and Preview chip with the frame area dark — a hierarchy capture cannot composite an AVPlayerLayer, so the poster frame is AVPlayerView's on-screen contract and the report is the driven truth
- [x] 3.3 The webm negative: opening one still shows the notice with Quick Look

## 4. Before finishing

- [x] 4.1 `make test` green (3940 tests, 2 known issues) at load 21.7; one earlier run flaked the pre-existing LSP 30 s bound at 43 s under load, green alone and in the clean run. `make warnings` clean; the three grown files re-recorded in the size ledger
- [x] 4.2 No `.abydos/backlog/spec/*.md` file is made untrue: how a video opens was unrecorded; the delta adds beside the picture requirement it imitates
