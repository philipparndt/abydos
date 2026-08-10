#!/bin/bash
#
# Does a profiler tell the truth about this build?
#
# `sample`, `atos` and Instruments identify a build by its LC_UUID, not by the
# path they were given: CoreSymbolication reads the UUID out of the Mach-O, asks
# the system which symbols belong to it, and uses the answer in preference to
# the file it was handed. `Scripts/pin-uuid.py` gives every local build the same
# UUID on purpose — see that file for why — so on a machine that has built this
# app more than once the question has several answers and the one chosen need
# not be this binary.
#
# Nothing fails. The tools print another build's function names, with source
# files and line numbers, and because every one of those names really does occur
# in this repository the result reads like a profile. 0428 read two of them and
# acted on them.
#
# So ask a question with a known answer: take the address the binary's own
# symbol table gives for `main` and ask `atos` what lives there. If it does not
# say `main`, nothing else it says about this build means anything either.
#
# Usage: Scripts/symbol-check.sh [mach-o]     (default: the built .app)

set -uo pipefail

cd "$(dirname "$0")/.."

BIN="${1:-build/Abydos.app/Contents/MacOS/Abydos}"
if [ ! -f "$BIN" ]; then
	echo "symbol-check: no such binary: $BIN" >&2
	echo "  build one first: make profile" >&2
	exit 2
fi

ARCH=$(lipo -archs "$BIN" 2>/dev/null | awk '{print $1}')
ARCH="${ARCH:-$(uname -m)}"
UUID=$(dwarfdump --uuid "$BIN" 2>/dev/null | awk '{print $2}' | head -1)

# `main` rather than something from this app: it is the one symbol an executable
# always has, it is never in a library that could legitimately shadow it, and it
# survives a release build. A Swift symbol would have to be chosen and could go
# away in a rename.
ADDR=$(nm -n "$BIN" 2>/dev/null | awk '$3 == "_main" { print $1; exit }')
if [ -z "$ADDR" ]; then
	echo "symbol-check: $BIN has no _main in its symbol table — stripped?" >&2
	exit 2
fi

ANSWER=$(atos -o "$BIN" -arch "$ARCH" "0x$ADDR" 2>/dev/null)
ADDR=$(printf '%x' $((16#$ADDR)))   # nm pads to sixteen digits; nobody reads those

case "$ANSWER" in
main*)
	echo "==> $BIN symbolicates as itself"
	echo "    main at 0x$ADDR, uuid $UUID"
	exit 0
	;;
esac

# Loud, and on stderr, because the whole failure mode is that it is quiet.
cat >&2 <<EOF

==> WRONG SYMBOLS: a profile of this build would name somebody else's code.

    $BIN
    uuid $UUID

    its own symbol table says   0x$ADDR is main
    atos, same address, says    ${ANSWER:-<nothing>}

    The UUID is how the tools decide which build a set of addresses belongs to,
    and this one is shared with every other build on this machine — deliberately;
    Scripts/pin-uuid.py says why. The symbol server answers for whichever of them
    it finds, and it is not this one.

    Build something a profiler can read:

        make profile              # release, PIN_UUID=0, and runs this check
        make build PIN_UUID=0     # the same by hand

EOF
exit 1
