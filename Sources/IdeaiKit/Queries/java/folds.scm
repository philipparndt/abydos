; tree-sitter-java ships no folds.scm, so this one is ours.
;
; Bodies rather than declarations: a fold keeps its first line visible, and a
; Java declaration begins at its annotations — folding `class_declaration`
; would hide the signature under `@Service` and leave the reader nothing to
; read. A body starts at the brace, which is nearly always on the signature's
; own line.
[
  (class_body)
  (interface_body)
  (enum_body)
  (annotation_type_body)
  (constructor_body)
  (block)
  (switch_block)
  (array_initializer)
  (block_comment)
] @fold
