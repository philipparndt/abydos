#!/bin/bash
# Puts a debugger for native programs into the development pod's rootfs.
#
# Delve debugs Go and nothing else, so a Zig, Odin, C, C++ or Rust program in a
# pod had nowhere to stop. gdbserver is what stops it: 640 KB, speaking the
# protocol LLDB already knows, so the debugger somebody looks at stays the one
# on their own machine.
#
# Taken from Alpine because its build is musl-linked and small — four files
# rather than the hundred megabytes a full toolchain would bring. The versions
# are read from the index rather than pinned, so this does not rot; the files
# are cached, so it runs once.
set -euo pipefail

arch="${1:?usage: fetch-gdbserver.sh <arm64|amd64> <rootfs>}"
rootfs="${2:?usage: fetch-gdbserver.sh <arm64|amd64> <rootfs>}"
release="${ALPINE_RELEASE:-v3.21}"

case "$arch" in
	arm64) machine=aarch64 ;;
	amd64) machine=x86_64 ;;
	*) echo "fetch-gdbserver: unknown architecture $arch" >&2; exit 2 ;;
esac

here="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$here/out"
cache="$here/out/alpine-$machine"
mirror="https://dl-cdn.alpinelinux.org/alpine/$release/main/$machine"
mkdir -p "$cache"

if [ ! -f "$cache/APKINDEX" ]; then
	curl -sfL "$mirror/APKINDEX.tar.gz" -o "$cache/index.tar.gz"
	tar xzf "$cache/index.tar.gz" -C "$cache" APKINDEX
fi

version() {
	# The version line that follows this package's name in the index.
	awk -v want="P:$1" '$0 == want { found = 1; next } found && /^V:/ { sub(/^V:/, ""); print; exit }' \
		"$cache/APKINDEX"
}

fetch() {
	local package="$1" version
	version="$(version "$package")"
	[ -n "$version" ] || { echo "fetch-gdbserver: no $package in $release/$machine" >&2; exit 1; }

	local file="$cache/$package-$version.apk"
	[ -f "$file" ] || curl -sfL "$mirror/$package-$version.apk" -o "$file"

	rm -rf "$cache/unpacked/$package"
	mkdir -p "$cache/unpacked/$package"
	tar xzf "$file" -C "$cache/unpacked/$package" 2>/dev/null || true
}

fetch gdb
fetch musl
fetch libstdc++
fetch libgcc

mkdir -p "$rootfs/usr/local/bin" "$rootfs/lib" "$rootfs/usr/lib"
cp "$cache/unpacked/gdb/usr/bin/gdbserver" "$rootfs/usr/local/bin/"
cp "$cache/unpacked/musl/lib/ld-musl-$machine.so.1" "$rootfs/lib/"
cp "$cache/unpacked/musl/lib/libc.musl-$machine.so.1" "$rootfs/lib/"
cp "$cache/unpacked/libgcc/usr/lib/libgcc_s.so.1" "$rootfs/usr/lib/"
# The real library, under the name its users ask for: the .so.6 in the package
# is a symlink, and a tarball of one points at nothing.
cp "$(ls "$cache/unpacked/libstdc++/usr/lib/"libstdc++.so.6.* | head -1)" "$rootfs/usr/lib/libstdc++.so.6"

printf '  gdbserver %s and its three libraries\n' "$(version gdb)"
