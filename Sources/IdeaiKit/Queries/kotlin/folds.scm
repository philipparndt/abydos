; tree-sitter-kotlin ships highlights and nothing else, so folding is ours.
;
; Bodies rather than declarations, for the reason Java's says: a fold shows its
; first line, and a Kotlin declaration starts at its annotations.
[
  (class_body)
  (enum_class_body)
  (function_body)
  (control_structure_body)
  (lambda_literal)
  (when_expression)
  (catch_block)
  (finally_block)
  (multiline_comment)
] @fold
