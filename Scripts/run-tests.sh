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
# **The status is carried out of the pipeline by hand, and that is not a
# flourish.** The run is backgrounded as a pipeline so its output can be watched
# and kept at the same time, and `$!` in a pipeline is the *last* command in it —
# `tee`. So `wait` reported whether `tee` had managed to write a file, which it
# always had, and `make test` exited 0 over a suite with failures in it. Three
# real failures were found in one afternoon only because somebody happened to be
# grepping the log; anything watching the exit code had been told the suite was
# green for as long as this script has existed.
#
# The command's own status goes into a file instead, and a run that leaves no
# status behind is a failed run rather than a silent one.
#
# Usage: run-tests.sh <seconds> <command...>

set -eu

timeout=$1
shift

log=$(mktemp -t abydos-tests)
status=$(mktemp -t abydos-tests-status)
trap 'rm -f "$log" "$status"' EXIT

# `set -m` puts the child in a process group of its own, so the negative pid
# below reaches the helper and the test bundle rather than only the shell.
#
# The shape of the pipeline is left exactly as it was — the kill below is aimed
# at it and works — and all that is added is the command's own status on its way
# past.
set -m
# `set +e` inside the group, and only there: with `errexit` on, the shell ends
# the subshell the moment the command fails and the line writing the status
# never runs — which turned every failing suite into "left no exit status
# behind", the right verdict for the wrong reason and with the wrong number.
# A pipeline element runs in a subshell, so this does not reach the script.
{ set +e; "$@" 2>&1; echo $? >"$status"; } | tee "$log" &
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

# `tee` is what this waits on — see above — so its answer is thrown away and the
# command's own is read from the file. `|| true` because `set -e` would
# otherwise end the script on a `tee` that was killed with the group.
wait "$pid" || true

# No status file means the run did not reach the end of the pipeline: killed,
# out of disk, a shell that could not fork. None of those is a pass.
if [ ! -s "$status" ]; then
	echo "==> The test run left no exit status behind — treating it as a failure."
	exit 1
fi

exit "$(cat "$status")"
