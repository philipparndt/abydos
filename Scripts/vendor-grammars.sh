#!/bin/bash
#
# Vendors the tree-sitter grammars whose own Package.swift cannot be used.
#
# Those manifests decide whether to compile the external scanner with:
#
#     if FileManager.default.fileExists(atPath: "src/scanner.c") { ... }
#
# That path is relative, and SPM does not evaluate manifests with the package
# checkout as the working directory, so the check is always false. The scanner is
# silently dropped and the grammar fails to link with undefined
# `tree_sitter_<lang>_external_scanner_*` symbols. Vendoring the sources lets us
# state the file list explicitly instead of depending on that check.
#
# Re-run to update: adjust the pinned tags below and run from the repo root.

set -euo pipefail

cd "$(dirname "$0")/.."
DEST="Sources/Grammars"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# name|repo|tag|c-symbol
GRAMMARS=(
	"CSS|https://github.com/tree-sitter/tree-sitter-css|v0.25.0|css"
	"JavaScript|https://github.com/tree-sitter/tree-sitter-javascript|v0.25.0|javascript"
	"Python|https://github.com/tree-sitter/tree-sitter-python|v0.25.0|python"
	"YAML|https://github.com/tree-sitter-grammars/tree-sitter-yaml|v0.7.2|yaml"
)

for entry in "${GRAMMARS[@]}"; do
	IFS='|' read -r NAME REPO TAG SYMBOL <<< "$entry"
	TARGET="$DEST/TreeSitter${NAME}Vendored"

	echo "==> $NAME ($TAG)"
	rm -rf "$TARGET"
	mkdir -p "$TARGET/src" "$TARGET/include" "$TARGET/queries"

	git clone --quiet --depth 1 --branch "$TAG" "$REPO" "$WORK/$NAME"

	# Every .c in src/ — some grammars (YAML) split the scanner across files,
	# which is exactly the case the upstream single-file check gets wrong.
	cp "$WORK/$NAME"/src/*.c "$TARGET/src/"
	if [ -d "$WORK/$NAME/src/tree_sitter" ]; then
		cp -R "$WORK/$NAME/src/tree_sitter" "$TARGET/src/"
	fi
	# Some scanners include local headers alongside the sources.
	cp "$WORK/$NAME"/src/*.h "$TARGET/src/" 2>/dev/null || true

	if [ -d "$WORK/$NAME/queries" ]; then
		cp "$WORK/$NAME"/queries/*.scm "$TARGET/queries/" 2>/dev/null || true
	fi

	# Public header declaring the entry point. Written rather than copied so the
	# path is predictable regardless of how upstream lays out its bindings.
	# (macOS ships bash 3.2, which has no ${VAR^^}, hence tr.)
	GUARD="$(printf '%s' "$SYMBOL" | tr '[:lower:]' '[:upper:]')"
	cat > "$TARGET/include/tree_sitter_${SYMBOL}.h" <<EOF
#ifndef TREE_SITTER_${GUARD}_VENDORED_H_
#define TREE_SITTER_${GUARD}_VENDORED_H_

typedef struct TSLanguage TSLanguage;

#ifdef __cplusplus
extern "C" {
#endif

const TSLanguage *tree_sitter_${SYMBOL}(void);

#ifdef __cplusplus
}
#endif

#endif
EOF

	echo "    sources: $(ls "$TARGET/src"/*.c | xargs -n1 basename | tr '\n' ' ')"
	echo "    queries: $(ls "$TARGET/queries" 2>/dev/null | tr '\n' ' ')"
done

echo "Done. Vendored grammars are in $DEST."
