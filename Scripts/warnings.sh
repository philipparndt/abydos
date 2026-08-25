#!/bin/bash
#
# Every warning this repository's code produces, and nothing else's.
#
# 0465 found eight warnings that had accumulated quietly, and by the time it was
# picked up there were fifteen: four had arrived that same day, in two merges,
# and nobody had done anything wrong. A warning is noticed once, by whoever
# happens to be looking at the tail of a build, and never again — because the
# next build is incremental and **only reports the files it recompiled**. That is
# the whole mechanism, and it is why counting them needs a build of its own.
#
#     make warnings
#
# Nothing depends on this. It is not wired into `make build` or `make test` and
# it is not `-warnings-as-errors`: a wall that stops work gets turned off, and a
# package with vendored upstream C in it could not have that wall anyway. It is
# one line somebody runs — before finishing a backlog item is the moment it was
# written for.
#
# ## What makes the answer complete without a cold build
#
# A clean scratch path recompiles everything, which for this package means
# eighteen grammar packages, a 20 MB generated Kotlin parser and draw.io — five
# minutes to be told about our own Swift. So instead: keep the scratch path, and
# delete the *package's* build directory inside it. Everything this repository
# compiles is then recompiled and everything anybody else's is not. Measured, on
# a ten-core machine with -j 4: 67 seconds against a cold build's several
# minutes, and no target list to keep in step with `Package.swift` — the rule is
# one path, `Abydos.build`, which is the package's own name.
#
# A scratch path of its own, and not the one `make build` uses, so running this
# does not throw away somebody's incremental build.
#
# ## What counts, and what does not
#
# - **Swift, ours** — a failure. Exit 1, and every one printed.
# - **Warnings out of a macro expansion** — a failure too, and they need saying
#   separately because the compiler prints them as `macro expansion @Test:13:183:`
#   with no file path on the line at all. Three of 0465's fifteen were these, and
#   the item's own `grep warning:` had missed all three. Anything that greps for
#   a `.swift:` will undercount; this greps for a warning.
# - **Vendored C** — reported, never a failure. `Sources/Grammars/*Vendored` is
#   upstream's code, re-vendored by `Scripts/vendor-grammars.sh`, and the four
#   `-Wshorten-64-to-32` in the Python and YAML scanners are theirs. Not silenced
#   with a flag on those targets: silencing the class would also silence a *new*
#   truncation at the next grammar bump, which is exactly the moment somebody
#   wants to see one. Counted here instead, so a bump that adds one is visible
#   without failing anybody's build.
# - **`missing creator for mutated node`** — SwiftPM's own, about GoSTL's bundle.
#   Named and ignored.
#
# Usage: Scripts/warnings.sh [--scratch <path>] [--jobs N]

set -uo pipefail

cd "$(dirname "$0")/.."

SCRATCH="build/warnings"
JOBS="${JOBS:-4}"

while [ $# -gt 0 ]; do
	case "$1" in
		--scratch) SCRATCH="$2"; shift 2 ;;
		--jobs) JOBS="$2"; shift 2 ;;
		*) echo "warnings: unknown argument: $1" >&2; exit 2 ;;
	esac
done

# How long the files are, before how much the compiler has to say about them.
#
# It needs no build, so it can say what is wrong before somebody waits a minute
# for the compiler — and when it is the only thing wrong, they know at once. It
# belongs under this verb for the reason the whole script exists: a complaint
# that only a build reports is seen once by whoever was watching the tail of it,
# and a file's length is exactly that kind of complaint. `Scripts/file-size.sh`
# says nothing at all when there is nothing to say.
Scripts/file-size.sh
SIZES=$?

LOG="$(mktemp -t abydos-warnings)"
trap 'rm -f "$LOG"' EXIT

# Everything this repository compiles, and nothing anybody else's.
rm -rf "$SCRATCH/out/Intermediates.noindex/Abydos.build"

# Both halves. The app and its libraries first, then the tests: `--build-tests`
# on its own does not build what only the executable reaches, and one of 0465's
# warnings lived in a file no test target sees.
echo "warnings: building Sources (this takes about a minute)…" >&2
xcrun swift build -j "$JOBS" --scratch-path "$SCRATCH" >"$LOG" 2>&1
SOURCES=$?
echo "warnings: building Tests…" >&2
xcrun swift build -j "$JOBS" --build-tests --scratch-path "$SCRATCH" >>"$LOG" 2>&1
TESTS=$?

if [ $SOURCES -ne 0 ] || [ $TESTS -ne 0 ]; then
	echo >&2
	echo "warnings: the build failed, so there is no list to give. The errors:" >&2
	sed $'s/\x1b\\[[0-9;]*m//g' "$LOG" | grep -E ': error: ' | sort -u >&2
	exit 2
fi

# Only lines that *start* a diagnostic. The compiler repeats each one inside an
# indented box of source context, and counting those would multiply everything.
#
# The awk is for the macro expansions and nothing else. A warning from inside one
# is printed as `macro expansion @Test:13:388: warning: …` with no file on the
# line at all, so on its own it is unactionable — and 0465's first count missed
# three of these entirely by grepping for a path. The context box printed beneath
# it does carry the `filePath:` and `line:` the macro was handed, so that is put
# back on the front.
#
# The line to take it from is the `expanded code originates here` note the
# compiler prints directly underneath, which is the only part of the whole block
# that names a file this repository has. It gives the end of the declaration the
# macro was attached to rather than the offending line — the macro expansion is
# where the offence is, and it has no line of ours — but naming the file and the
# declaration is what makes the warning something somebody can go and look at.
PLAIN="$(sed $'s/\x1b\\[[0-9;]*m//g' "$LOG" | awk '
	function flush() { if (pending != "") { print "(file not given) " pending; pending = "" } }

	pending != "" && /^`- .*: note: expanded code originates here/ {
		where = $0
		sub(/^`- /, "", where)
		sub(/: note: expanded code originates here.*$/, "", where)
		print where ": " pending
		pending = ""
		next
	}
	/^macro expansion .*: warning: / {
		flush()
		pending = $0
		sub(/^macro expansion [^ ]+: /, "", pending)
		next
	}
	/^[^[:space:]`].*: warning: / { flush(); print; next }
	END { flush() }
' | sort -u)"

GRAMMARS='/Sources/Grammars/[A-Za-z]*Vendored/'
VENDORED="$(printf '%s\n' "$PLAIN" | grep -E "$GRAMMARS")"
OURS="$(printf '%s\n' "$PLAIN" \
	| grep -vE "$GRAMMARS" \
	| grep -vE '^warning: missing creator for mutated node')"

count() { [ -z "$1" ] && echo 0 || printf '%s\n' "$1" | grep -c . ; }

VENDORED_COUNT=$(count "$VENDORED")
OURS_COUNT=$(count "$OURS")

if [ "$VENDORED_COUNT" -gt 0 ]; then
	echo
	echo "Vendored C, upstream's to fix and not ours ($VENDORED_COUNT):"
	printf '%s\n' "$VENDORED" | sed "s|$PWD/||" | sed 's/^/  /'
fi

echo
if [ "$OURS_COUNT" -eq 0 ]; then
	echo "No warnings in this repository's Swift. Keep it that way."
	# A file over the ceiling is still something this verb found, and its exit
	# code has to say so — the whole argument for trusting these codes is that
	# they mean what they say.
	exit $SIZES
fi

echo "$OURS_COUNT warning(s) in this repository's Swift:"
printf '%s\n' "$OURS" | sed "s|$PWD/||" | sed 's/^/  /'
echo
echo "Sort them before fixing them. 0465 is the argument: of fifteen, two were"
echo "the compiler being right about a lifetime bug, five were errors waiting in"
echo "the Swift 6 language mode, and three were tests asserting nothing. A sweep"
echo "of \`_ =\` and \`let\` would have hidden all ten."
exit 1
