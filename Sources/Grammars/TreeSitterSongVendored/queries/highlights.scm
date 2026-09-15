; Highlights for musik-as-text .song files.
;
; Every node gets at most one capture, so the result does not depend on how an
; editor orders overlapping captures.

(comment) @comment

; ---------------------------------------------------------------- blocks

[
  "title"
  "tempo"
  "meter"
  "swing"
  "seed"
  "section"
  "instrument"
  "preset"
  "pattern"
  "track"
  "master"
  "play"
] @keyword

; instrument lead synth | pattern verse | track drums | section chorus
(name) @function

; synth, drums, tb303 ... and the preset after `preset`
(instrument_kind) @type
(preset_name) @type

; pattern beat grid pedal
(pattern_block (identifier) @attribute)

; ---------------------------------------------------------------- settings

; osc, filter, gain, sidechain, sweep ...
(setting_name) @property

; osc saw | filter lowpass | limiter off
(setting (identifier) @type.builtin)

; play verse | instrument lead | sidechain drums | layer drums
(reference) @variable

; sweep cutoff
(parameter) @variable.parameter

; key=value
(key) @property
"=" @operator
(option value: (identifier) @constant)

; ---------------------------------------------------------------- values

(string) @string

[
  (number)
  (fraction)
  (range)
  (repeat_count)
] @number

; ---------------------------------------------------------------- notes

[
  (note)
  (note_range)
  (drum)
] @constant

(rest) @constant.builtin

":" @punctuation.delimiter
(duration) @attribute

"@" @label
(velocity) @label

(articulation) @operator

(bar) @punctuation.delimiter

[
  "["
  "]"
] @punctuation.bracket

; ---------------------------------------------------------------- grids

(grid_hit) @string
(grid_hold) @operator
(grid_rest) @punctuation.delimiter
