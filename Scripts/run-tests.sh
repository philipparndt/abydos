#!/bin/sh
# Runs the test suite under a deadline it cannot outlive.
#
# A test that hangs costs more than a test that fails: the run says nothing,
# the terminal sits there, and the process that is actually stuck is not the
# one being watched — `swift test` spawns `swiftpm-testing-helper`, which
# spawns the test bundle, and killing the top one by hand leaves the bundle
# running for ever with nobody waiting for it. That has happened repeatedly,
# and every time it cost the rest of an afternoon.
#
# So the whole run goes in a process group of its own and the group is killed
# together. What is left behind is the output up to the moment it stopped,
# which names the test that was running when the clock ran out.
#
# Usage: run-tests.sh <seconds> <command...>

set -eu

timeout=$1
shift

log=$(mktemp -t abydos-tests)
trap 'rm -f "$log"' EXIT

# `set -m` puts the child in a process group of its own, so the negative pid
# below reaches the helper and the test bundle rather than only the shell.
set -m
"$@" 2>&1 | tee "$log" &
pid=$!
set +m

waited=0
while kill -0 "$pid" 2>/dev/null; do
	if [ "$waited" -ge "$timeout" ]; then
		echo ""
		echo "==> No answer after ${timeout}s. Killing the run."
		# The last test the runner said it had started, which is the one that
		# hung unless the runner itself did.
		last=$(grep -E 'Test .* started' "$log" | tail -1)
		[ -n "$last" ] && echo "    last started: $last"
		echo "    raise it with: make test TEST_TIMEOUT=<seconds>"
		kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
		sleep 2
		kill -KILL -"$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
		# Anything that outlived its parent anyway. A test bundle re-parented to
		# launchd is exactly what this script exists to prevent being left.
		pkill -KILL -f 'swiftpm-testing-helper.*AbydosKitTests' 2>/dev/null || true
		exit 124
	fi
	sleep 1
	waited=$((waited + 1))
done

wait "$pid"
