# A shaped run remembered by its text must not remember its column

`8e6281935` · 2026-08-08

Text piled on top of other text, with ligatures on. The cache is keyed by
the run's characters and the face, which is the point of it — a terminal
draws the same prompt segment and the same operators over and over — but
each piece carried the *column* it had been shaped at. So the second
occurrence of a run was drawn at the first one's columns, and the same
prompt appearing twice on a line put one on top of the other.

Offsets are relative to the run now, and the column is added where they
are used. Which is what a cache keyed by text alone requires: nothing in
the answer may depend on where the question was first asked.

The test asserts that directly — that no offset from a two-cell run is
ever two or more, since an offset past the run is a column in disguise.

Found from a screenshot rather than by reasoning, which is worth saying:
the per-run cache looked obviously right and was obviously wrong the
moment two runs matched.
