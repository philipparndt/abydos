#!/bin/bash
# Two windows of a built Abydos sharing one tmux server, driven through every
# case `project-windows` names, each from a fresh server and a fresh app.
#
# Nothing here reaches somebody's tmux: the server is a scratch one under a
# temporary directory, started with `-f /dev/null` so no config or continuum
# restores real sessions into it, and the app finds it through a `tmux` shim at
# the front of its PATH. The projects are empty repositories in that directory,
# and the app is stopped by the pid this script started, never by name.
#
#   Scripts/windows-check.sh [APP] [SCENARIO...]
#
# A client is moved the way `C-b w` moves it — `switch-client -t =session:window`
# from outside the app — and the app is then given three seconds, six of its
# half-second readings, before where every client is gets asserted.
set -u

APP=${1:-build/Abydos.app/Contents/MacOS/Abydos}
shift $(( $# > 0 ? 1 : 0 ))
ONLY=("$@")
REAL_TMUX=${REAL_TMUX:-/opt/homebrew/bin/tmux}
LOG=~/Library/Logs/Abydos/tmux.log

[ -x "$APP" ] || { echo "no app at $APP (make build BUNDLE_ID=... PIN_UUID=0)"; exit 2; }
[ -x "$REAL_TMUX" ] || { echo "no tmux at $REAL_TMUX"; exit 2; }

WORK=$(cd "$(mktemp -d /private/tmp/abydos-windows.XXXXXX)" && pwd -P)
SOCK=$WORK/s
OUTER=$WORK/o
P=$WORK/p
mkdir -p "$WORK/bin" "$P"
cat > "$WORK/bin/tmux" <<EOF
#!/bin/sh
exec "$REAL_TMUX" -f /dev/null -S "$SOCK" "\$@"
EOF
chmod +x "$WORK/bin/tmux"
for name in AbydosDev website Usermanual; do git init -q "$P/$name"; done

t() { "$REAL_TMUX" -f /dev/null -S "$SOCK" "$@"; }
outer() { "$REAL_TMUX" -f /dev/null -S "$OUTER" "$@"; }

PID=
cleanup() {
	[ -n "$PID" ] && kill "$PID" 2>/dev/null && wait "$PID" 2>/dev/null
	outer kill-server 2>/dev/null
	t kill-server 2>/dev/null
	rm -rf "${WORK:?}"
}
trap cleanup EXIT

PASSED=0
FAILED=0
FAILURES=()
CURRENT=

pass() { PASSED=$((PASSED + 1)); echo "    ok   $1"; }
fail() { FAILED=$((FAILED + 1)); FAILURES+=("$CURRENT: $1"); echo "    FAIL $1"; }

# The server every scenario starts from: the person's example.
fresh_server() {
	outer kill-server 2>/dev/null
	t kill-server 2>/dev/null
	t new -d -s AbydosDev -n Claude -c "$P/AbydosDev" -x 100 -y 30
	t neww -d -t =AbydosDev: -n Tests -c "$P/AbydosDev"
	t neww -d -t =AbydosDev: -n Infra -c "$P/AbydosDev"
	t new -d -s website -n Site -c "$P/website"
	t neww -d -t =website: -n Build -c "$P/website"
	t new -d -s Usermanual -n Docs -c "$P/Usermanual"
	t neww -d -t =Usermanual: -n Deployment -c "$P/Usermanual"
	t set -g aggressive-resize on
}

# A terminal in another program — another copy of Abydos, iTerm — attached to
# `$1` and showing window `$2`: a client of a second scratch server.
outside_client() {
	t select-window -t "=$1:$2"
	outer new -d -s out -x 100 -y 30 "env -u TMUX '$REAL_TMUX' -f /dev/null -S '$SOCK' attach -t '=$1'"
	wait_for "outside client" "[ \$(t list-clients | wc -l) -ge 1 ]"
	OUTSIDE=$(t list-clients -F '#{client_tty}' | head -1)
}

wait_for() {
	local what=$1 condition=$2
	for _ in $(seq 1 40); do eval "$condition" && return 0; sleep 0.5; done
	fail "timed out waiting for $what"
	return 1
}

# Window 1 on AbydosDev, window 2 on `$2` (website unless said), as the app's own
# verbs open them; `$1` is "mirrored" for tabs that mirror tmux.
launch() {
	local mode=$1 second=${2:-website} before
	before=$(t list-clients | wc -l | tr -d ' ')
	local extra=(--second-window "$P/$second")
	[ "$mode" = mirrored ] && extra+=(--tmux-tabs)
	extra+=(${LAUNCH_EXTRA[@]+"${LAUNCH_EXTRA[@]}"})
	env -u TMUX PATH="$WORK/bin:$PATH" "$APP" --open "$P/AbydosDev" "${extra[@]}" \
		> "$WORK/out" 2> "$WORK/err" &
	PID=$!
	wait_for "two windows attached" "[ \$(t list-clients | wc -l) -ge $((before + 2)) ]" || return 1
	# Foundation's resolved path drops the /private that /tmp stands for.
	if ! grep -q -e "^project $P/AbydosDev\$" -e "^project ${P#/private}/AbydosDev\$" "$WORK/err"; then
		fail "the app opened something other than $P/AbydosDev; stopped"
		return 1
	fi
	sleep 2
	W1=$(client_on AbydosDev)
	W2=$(client_on "${SECOND_SESSION:-$second}" "$W1")
	[ -n "$W1" ] && [ -n "$W2" ] || { fail "cannot tell the two windows' clients apart: $(t list-clients -F '#{client_tty}:#{client_session}' | tr '\n' ' ')"; return 1; }
}

# The tty of the app's client on `$1` or a session grouped with it, not `$2`
# and not the outside one.
client_on() {
	t list-clients -F '#{client_created} #{client_tty} #{client_session}' | sort -n | while read -r _ tty session; do
		[ "$tty" = "${2:-}" ] || [ "$tty" = "${OUTSIDE:-}" ] && continue
		case $session in "$1"|"$1~"*) echo "$tty"; break ;; esac
	done
}

stop_app() {
	[ -n "$PID" ] || return
	kill "$PID" 2>/dev/null
	wait "$PID" 2>/dev/null
	PID=
	sleep 1
}

# `C-b w` in the window whose client is `$1`, choosing `$2` (session:window).
choose() {
	MARK=$(wc -l < "$LOG" | tr -d ' ')
	t switch-client -c "$1" -t "=$2"
	sleep 3
}

where() { t list-clients -F '#{client_tty} #{client_session} #{window_name}' | awk -v tty="$1" '$1 == tty { $1 = ""; print substr($0, 2) }'; }

# `$1` shows window `$3` in session `$2` (a glob: AbydosDev* takes a grouped one).
expect_on() {
	local got session window
	got=$(where "$1")
	session=${got% *}
	window=${got##* }
	# shellcheck disable=SC2053
	if [[ $session == $2 && $window == "$3" ]]; then pass "$4 shows $3 in $session"
	else fail "$4 should show $3 in $2, shows ${window:-nothing} in ${session:-nothing}"; fi
}

expect_logged() {
	if tail -n +"$((MARK + 1))" "$LOG" | grep -q "$1"; then pass "$2"
	else fail "$2 — no '$1' in tmux.log"; fi
}

expect_not_logged() {
	if tail -n +"$((MARK + 1))" "$LOG" | grep -q "$1"; then fail "$2 — '$1' in tmux.log"
	else pass "$2"; fi
}

expect_left_tmux() {
	local got
	got=$(where "$1")
	if [ -z "$got" ]; then pass "$2 has left tmux"
	else fail "$2 should have left tmux, shows $got"; fi
}

expect_sessions() {
	local got
	got=$(t list-sessions -F '#{session_name}' | grep -c -- "$1")
	if [ "$got" = "$2" ]; then pass "$3"
	else fail "$3 — $got sessions match '$1': $(t list-sessions -F '#{session_name}' | tr '\n' ' ')"; fi
}

# ---------------------------------------------------------------- scenarios

# Window 2 looks at another tmux window of window 1's session.
scenario_second_looks_elsewhere() {
	choose "$W2" AbydosDev:Tests
	expect_on "$W2" 'AbydosDev~*' Tests "window 2"
	expect_on "$W1" AbydosDev Claude "window 1"
}

# Window 2 chooses, from another session, the tmux window window 1 shows.
scenario_onto_first_from_another_session() {
	choose "$W2" AbydosDev:Claude
	expect_logged "step away" "window 1 raised"
	expect_on "$W2" website Site "window 2 back"
	expect_on "$W1" AbydosDev Claude "window 1"
	expect_sessions '~' 0 "no grouped session left behind"
}

# Window 2, already in the group, chooses the tmux window window 1 shows.
scenario_onto_first_within_the_group() {
	choose "$W2" AbydosDev:Tests
	choose "$W2" AbydosDev:Claude
	expect_logged "step away" "window 1 raised"
	expect_on "$W2" 'AbydosDev~*' Tests "window 2 back"
	expect_on "$W1" AbydosDev Claude "window 1"
}

# Window 1 chooses the tmux window window 2 moved to — the other way round.
scenario_first_onto_second() {
	choose "$W2" AbydosDev:Tests
	choose "$W1" AbydosDev:Tests
	expect_logged "step away" "window 2 raised"
	expect_on "$W1" 'AbydosDev*' Claude "window 1 back"
	expect_on "$W2" 'AbydosDev~*' Tests "window 2"
}

# A window whose group was a grouped session of its own goes back through a
# new one: reported 2026-11-09, `abydos~2` was gone and the two stayed on one.
scenario_back_to_a_grouped_session_that_went() {
	choose "$W2" Usermanual:Docs
	choose "$W1" Usermanual:Docs
	expect_logged "step away" "window 2 raised"
	expect_on "$W1" 'AbydosDev*' "$FIRST_SHOWN" "window 1 back"
	expect_on "$W2" Usermanual Docs "window 2"
	expect_on "$OUTSIDE" AbydosDev Claude "the other program's terminal"
}

# A terminal in another program on the session makes window 1 a grouped one,
# beside it, and a C-b w through that session puts the other terminal back.
scenario_another_program_on_the_session() {
	expect_on "$W1" 'AbydosDev~*' "$FIRST_SHOWN" "window 1 grouped"
	[ "$FIRST_SHOWN" != Claude ] && pass "window 1 is not on the other program's window" \
		|| fail "window 1 started on the other program's window"
	choose "$W2" AbydosDev:Infra
	expect_on "$W2" 'AbydosDev~*' Infra "window 2"
	expect_on "$OUTSIDE" AbydosDev Claude "the other program's terminal"
}

# A grouped session goes with the window that leaves it.
scenario_grouped_session_goes() {
	choose "$W2" AbydosDev:Tests
	expect_sessions '~' 1 "one grouped session while window 2 is in the group"
	choose "$W2" Usermanual:Docs
	expect_sessions '~' 0 "none once it has left"
}

# Somebody closes the tmux window window 2 shows (`C-x y`), and tmux puts it on
# the one window 1 has in front. Reported 2026-11-09: the two then shared it, and
# typing went to both. It moves to a free window instead, raising nothing.
scenario_closed_under_the_second() {
	choose "$W2" AbydosDev:Tests
	MARK=$(wc -l < "$LOG" | tr -d ' ')
	t kill-window -t '=AbydosDev:Tests'
	sleep 3
	expect_not_logged "step away" "window 1 not raised"
	expect_on "$W2" 'AbydosDev~*' Infra "window 2 on the free window"
	expect_on "$W1" AbydosDev Claude "window 1"
}

# The same with no free window left: window 2's terminal leaves tmux.
scenario_closed_under_the_second_nothing_free() {
	choose "$W2" AbydosDev:Tests
	t kill-window -t '=AbydosDev:Infra'
	sleep 3
	MARK=$(wc -l < "$LOG" | tr -d ' ')
	t kill-window -t '=AbydosDev:Tests'
	sleep 3
	expect_not_logged "step away" "window 1 not raised"
	expect_left_tmux "$W2" "window 2"
	expect_on "$W1" AbydosDev Claude "window 1"
	expect_sessions '~' 0 "its grouped session went with it"
}

# The other way round: window 1's window closes and tmux puts it on window 2's.
scenario_closed_under_the_first_nothing_free() {
	choose "$W2" AbydosDev:Tests
	t kill-window -t '=AbydosDev:Infra'
	sleep 3
	MARK=$(wc -l < "$LOG" | tr -d ' ')
	t kill-window -t '=AbydosDev:Claude'
	sleep 3
	expect_not_logged "step away" "window 2 not raised"
	expect_left_tmux "$W1" "window 1"
	expect_on "$W2" 'AbydosDev~*' Tests "window 2"
}

# A window joining a group starts beside the other's tmux window.
scenario_joins_beside() {
	expect_on "$W2" 'AbydosDev~*' Tests "window 2 joined beside"
	expect_on "$W1" AbydosDev Claude "window 1"
}

run() {
	local name=$1 mode=$2 setup=${3:-}
	CURRENT="$name ($mode)"
	if [ ${#ONLY[@]} -gt 0 ] && [[ ! " ${ONLY[*]} " == *" $name "* ]]; then return; fi
	echo "  $CURRENT"
	OUTSIDE=
	LAUNCH_EXTRA=()
	SECOND_SESSION=
	[ "$setup" = joins ] && SECOND_SESSION=AbydosDev
	fresh_server
	local second=website
	case $setup in
		outside) outside_client AbydosDev Claude ;;
		joins) LAUNCH_EXTRA=(--second-window-session AbydosDev) ;;
	esac
	if launch "$mode" "$second"; then
		FIRST_SHOWN=$(where "$W1"); FIRST_SHOWN=${FIRST_SHOWN##* }
		MARK=$(wc -l < "$LOG" | tr -d ' ')
		"scenario_$name"
	fi
	stop_app
	expect_sessions '~' 0 "nothing grouped left once the app has quit"
}

echo "windows-check: $APP against a scratch server in $WORK ($(sysctl -n vm.loadavg))"
for mode in plain mirrored; do
	run second_looks_elsewhere "$mode"
	run onto_first_from_another_session "$mode"
	run onto_first_within_the_group "$mode"
	run first_onto_second "$mode"
	run back_to_a_grouped_session_that_went "$mode" outside
	run another_program_on_the_session "$mode" outside
	run grouped_session_goes "$mode"
	run joins_beside "$mode" joins
	run closed_under_the_second "$mode"
	run closed_under_the_second_nothing_free "$mode"
	run closed_under_the_first_nothing_free "$mode"
done

echo
echo "windows-check: $PASSED passed, $FAILED failed (load $(sysctl -n vm.loadavg))"
for failure in "${FAILURES[@]+"${FAILURES[@]}"}"; do echo "  $failure"; done
[ "$FAILED" -eq 0 ]
