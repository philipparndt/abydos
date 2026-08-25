#!/bin/bash
#
# How long a source file in this repository is allowed to be.
#
# A file that cannot be held in mind stops being read and starts being appended
# to. `MainWindowController.swift` is what that looks like at the far end: 13,030
# lines, 674 members in one `final class`, and a `// MARK` section headed **Zoom**
# holding 1,576 lines of sidebar tools, git pages and driving verbs. Nobody
# decided that section should contain those things — it is where the cursor was.
# By then the headings no longer described what was under them, so the file had
# to be measured rather than skimmed to find out what was in it.
#
#     Scripts/file-size.sh
#
# The ceiling is 1,000 lines. The number is round and that is not the point; the
# point is that it is checked rather than merely stated, because the rule it
# replaces — everybody agreeing that files should be smallish — is the rule that
# produced the 13,030.
#
# It is a limit on the *file*, which is the unit somebody opens, and not on the
# type. Where a type genuinely wants more than a thousand lines what it wants is
# collaborators that own their own state, not the same state spread over more
# files: Swift's `private` is visible only within the declaring file, so
# splitting a class into extensions across files costs exactly as much
# encapsulation as the number of properties the other files need. Smaller files,
# the same god object, and less encapsulation than it started with.
#
# ## Why there is a list of exceptions
#
# Twenty-seven files were over the ceiling on the day this was written, 71,296
# lines between them and 44,296 lines of excess. A check that failed on all of
# them would have been switched off the same afternoon, and a check that was
# switched off teaches that the checks in this repository are advisory — which is
# a more expensive lesson than any one file.
#
# So `Scripts/file-size-allowed.txt` is that debt, written down, at the lengths
# those files were. A listed file may shrink freely; it may not grow. When it
# comes under the ceiling it is struck from the list and cannot go back on.
# The list is empty when the work is done, and this script then needs no list.
#
# A file that is shorter but still over the ceiling passes silently and its
# recorded number is left alone, so that somebody shortening a file is not also
# obliged to edit a manifest to stay green. Tightening the number is a choice
# somebody makes.
#
# ## What is not checked
#
# `Tests` is left out. A test file is a list of claims rather than a machine, and
# it is read a claim at a time; three of them are over the ceiling and none of
# them is hard to navigate. If that stops being true it is a change of its own.
#
# Every vendored file in this repository is C, under `Sources/Grammars`, so there
# is nothing to exclude here today. A vendored *Swift* file arriving would be
# listed like anything else, which is the right way round: it should be noticed.

set -uo pipefail

cd "$(dirname "$0")/.."

CEILING=1000
LIST="Scripts/file-size-allowed.txt"

if [ ! -f "$LIST" ]; then
	echo "file-size: no $LIST — every file over $CEILING lines would be a fault." >&2
	exit 2
fi

# Every fault, sorted by how far over each file is, and then one exit code.
#
# Stopping at the first would turn one run into as many runs as there are files
# at fault, and this check is cheap enough that there is no reason to.
FAULTS=""
NOTES=""

fault() { FAULTS="${FAULTS}$1"$'\n'; }
note()  { NOTES="${NOTES}$1"$'\n'; }

while IFS= read -r file; do
	lines=$(wc -l < "$file" | tr -d ' ')
	allowed=$(awk -v f="$file" '$2 == f { print $1; exit }' "$LIST")

	if [ -z "$allowed" ]; then
		[ "$lines" -gt "$CEILING" ] \
			&& fault "$((lines - CEILING))	$file is $lines lines, over the $CEILING-line ceiling"
	elif [ "$lines" -gt "$allowed" ]; then
		fault "$((lines - CEILING))	$file has grown to $lines lines, recorded at $allowed"
	elif [ "$lines" -le "$CEILING" ]; then
		note "$file is $lines lines and may be struck from $LIST"
	fi
done < <(find Sources -name '*.swift' -type f | sort)

# An entry naming a file that is no longer there is stale rather than wrong: the
# file was deleted, or renamed — and a rename shows up as its new name being
# unlisted and over the ceiling, which is a fault above and reads better there.
while read -r _ file; do
	[ -n "$file" ] && [ ! -f "$file" ] \
		&& note "$file is no longer in the tree and may be struck from $LIST"
done < "$LIST"

if [ -n "$NOTES" ]; then
	echo
	printf '%s' "$NOTES" | sed 's/^/  /'
fi

if [ -z "$FAULTS" ]; then
	exit 0
fi

echo
echo "$(printf '%s' "$FAULTS" | grep -c .) file(s) over the $CEILING-line ceiling:"
printf '%s' "$FAULTS" | sort -rn | cut -f2- | sed 's/^/  /'
echo
echo "A file gets under the ceiling by state moving out of it, not by braces"
echo "moving: an extension in another file cannot see \`private\`, so splitting a"
echo "class that way widens every property the new file touches."
exit 1
