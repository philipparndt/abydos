#!/bin/bash
# Opens a real project and says what it cost.
#
# 0428's harness. The engine half of the same question lives in
# `ScaleLiveTests` and runs under `swift test`, because the tree, `git status`,
# the language-server scan and search all work without a window. This is the
# other half — the numbers that only exist when there *is* a window: how long
# until one appeared, how long until the thing in it was usable, what the app
# and the language server weigh while it settles, and what a keystroke costs in
# a file inside a large bundle.
#
# By hand rather than in CI, which is the second question the item leaves open.
# A run is minutes and needs several gigabytes of somebody else's source; what
# it produces is a baseline to compare against, not a gate, and a gate that
# needed a 763 MB checkout would be a gate that was always skipped.
#
#   Scripts/scale.sh ~/dev/abydos-corpus/sirius
#   FILE=plugins/…/Foo.java Scripts/scale.sh ~/dev/abydos-corpus/sirius
#   AT=5,30,90 PRESSES=200 Scripts/scale.sh <project>
#
# `FILE` is relative to the project and is what the keystrokes go into, so it
# should be a real file in a large bundle rather than a scratch one — the whole
# question is what typing costs *there*. It is restored with `git checkout`
# afterwards: the editor auto-saves, and a harness that leaves two hundred
# letters of `abcdef` in somebody's corpus has quietly changed what the next run
# measures.
#
# Take one at a time and take nothing else while it runs. Every number here is
# a wall clock over work the operating system schedules, and the load average is
# printed beside each reading precisely so that a reader can tell whether it was
# measuring the app or the machine.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="${1:-}"
[ -n "$PROJECT" ] || { echo "usage: Scripts/scale.sh <project> [--file <path in project>]"; exit 2; }
shift
PROJECT="$(cd "$PROJECT" && pwd)"

# When to read. Three times rather than once, because a project this size is
# still settling at every one of them and a single reading cannot tell
# "finished" from "not yet" — 0433's lesson, and much louder here.
AT="${AT:-5,30,90}"
LAST="${AT##*,}"
APP="build/Abydos.app/Contents/MacOS/Abydos"
test -x "$APP" || { echo "no $APP — run make build first"; exit 1; }

say() { printf '\n== %s\n' "$1"; }

say "$PROJECT"
echo "   app     $($APP --version | head -1)"
echo "   load    $(uptime | sed 's/.*load averages*: //')"
echo "   readings at ${AT}s"

# `git status` from the outside as well as from the app, because the two answer
# different questions: the app's number includes parsing the porcelain and
# colouring the tree, and this one is the floor under it that no amount of our
# code can get below.
# `rev-parse` rather than `test -d .git`: in a worktree `.git` is a *file*
# pointing at the real one, and the directory test said "no repository here"
# about a checkout that plainly is one.
if git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
	say "git status, from the shell"
	# Warm first and then timed, so what is measured is the steady state the
	# tree sees on its second and every later filesystem event rather than a
	# cold index nobody has after the first minute of work.
	git -C "$PROJECT" status --porcelain >/dev/null 2>&1 || true
	for round in 1 2 3; do
		start=$(python3 -c 'import time; print(time.monotonic())')
		changed=$(git -C "$PROJECT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
		python3 -c "import time,sys; print('   run $round  %8.1f ms, $changed changed' % ((time.monotonic()-$start)*1000))"
	done
	echo "   load    $(uptime | sed 's/.*load averages*: //')"
else
	say "git status: no repository at this root, so nothing colours this tree"
fi

# The app itself. The binary directly rather than `open -a`: an Abydos is very
# likely already running from /Applications, and `open` would hand the request
# to *that* one — which is how a driver came to rename a file in somebody's real
# ~/.config while its author believed it was looking at a corpus.
say "opening it"
LOG="${LOG:-$(mktemp -t abydos-scale)}"
# `--close-window` and not `--stop-after`: the second stops a *run
# configuration*, which this has none of, so the app sat there until something
# killed it and nothing was ever flushed. Closing the last window terminates the
# app, which is the path a person takes and therefore the one worth exercising.
FILE_ARGS=()
if [ -n "${FILE:-}" ]; then
	FILE_ARGS=(--file "$PROJECT/$FILE")
	echo "   typing into $FILE"
fi

# `${FILE_ARGS[@]+…}` rather than a bare expansion. bash 3.2 is what macOS
# ships, and under `set -u` it calls an *empty* array unbound — so the first run
# taken without a FILE launched no app at all and then printed ninety seconds of
# "not running" beside a falling load average. A table of readings about nothing,
# which is the failure the project guard at the bottom exists for.
"$APP" --open "$PROJECT" --report-open "$AT" --report-typing "${PRESSES:-200}" \
	${FILE_ARGS[@]+"${FILE_ARGS[@]}"} \
	--close-window "$(python3 -c "print($LAST + 5)")" "$@" >"$LOG" 2>&1 &
APP_PID=$!

# Whatever happens below, this app does not outlive the harness and the file it
# typed into goes back the way it was. A run that leaves a second Abydos holding
# a language server is the next run's noise — 0427 is about that shape of
# leftover — and a corpus with the harness's own keystrokes saved into it is a
# corpus that no longer matches the one the numbers were taken on.
restore() {
	kill "$APP_PID" 2>/dev/null || true
	if [ -n "${FILE:-}" ]; then
		git -C "$PROJECT" checkout -- "$FILE" 2>/dev/null \
			&& echo "   put $FILE back" \
			|| echo "   COULD NOT put $FILE back — check it by hand"
	fi
}
trap restore EXIT

# What it weighs, and what the language server beside it weighs, sampled while
# it settles. `rss` is the resident size and `time` is processor time, and the
# second is the one that answers "how much of this is somebody else's indexer":
# a jdtls at 4 minutes of processor time is doing something, whatever the wall
# clock says about it.
printf '\n   %7s  %-26s  %-26s  %s\n' at "ours rss/cpu/%" "jdtls rss/cpu/%" load
for second in $(seq 0 10 "$(python3 -c "print(int($LAST))")"); do
	ours=$(ps -o rss=,time=,pcpu= -p "$APP_PID" 2>/dev/null | head -1 | xargs || true)
	# **Only this app's own children.** The first version of this asked `ps` for
	# any process whose command line named jdtls, and on this machine that found
	# the language server belonging to the Abydos already running out of
	# /Applications — somebody else's indexer, reported as the cost of opening
	# this corpus. A number that is 90% somebody else's is worth having as long
	# as it says so; a number that is 100% somebody else's while claiming to be
	# ours is worse than none.
	#
	# Largest of them, because jdtls is a launcher and a JVM and, while it is
	# resolving Maven dependencies, whatever it forked; the one worth reporting
	# is the one holding the index.
	jdtls=$(for child in $(pgrep -P "$APP_PID" 2>/dev/null || true); do
			ps -o rss=,time=,pcpu=,command= -p "$child" 2>/dev/null
		done | grep -i 'jdt[._-]\{0,1\}ls\|org.eclipse.jdt.ls\|java' \
		| sort -rn | head -1 | awk '{print $1, $2, $3}' | xargs || true)
	printf '   %6ss  %-26s  %-26s  %s\n' "$second" "${ours:-not running}" "${jdtls:-none}" \
		"$(uptime | sed 's/.*load averages*: //')"
	sleep 10
done

wait "$APP_PID" 2>/dev/null || true

say "what it said"
grep -E '^OPEN' "$LOG" || echo "   nothing — see $LOG"

# The guard, last so it is the final word: a report whose project line is not
# the project asked for is a report about whatever was open last, and those look
# exactly like an answer.
if grep -q "^OPEN project $PROJECT\$" "$LOG"; then
	echo
	echo "   ✓ this was $PROJECT"
else
	echo
	echo "   ✗ the window was NOT on $PROJECT — every number above is about something else"
	grep '^OPEN project' "$LOG" || true
	exit 1
fi
echo "   log $LOG"
