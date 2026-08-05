#!/bin/bash
# Puts a JVM into the development pod's rootfs.
#
# A jar cannot be executed the way every other artefact this pod runs can:
# something has to run it. That something is also the debugger — a JVM given
# `-agentlib:jdwp` is one — so this is the whole of what a Java pod needs, and
# there is no Delve or gdbserver in the jvm variant at all.
#
# Temurin's alpine-linux build, because it is musl-linked and the rest of this
# image already is: the four libraries below are the same ones gdbserver needs.
# A hundred megabytes against the ten a Go pod costs, which is why it is a
# variant of its own rather than something the full image carries.
set -euo pipefail

arch="${1:?usage: fetch-jre.sh <arm64|amd64> <rootfs>}"
rootfs="${2:?usage: fetch-jre.sh <arm64|amd64> <rootfs>}"
release="${ALPINE_RELEASE:-v3.21}"
java="${JAVA_VERSION:-21}"

case "$arch" in
	arm64) machine=aarch64; adoptium=aarch64 ;;
	amd64) machine=x86_64;  adoptium=x64 ;;
	*) echo "fetch-jre: unknown architecture $arch" >&2; exit 2 ;;
esac

here="$(cd "$(dirname "$0")/.." && pwd)"
cache="$here/out/alpine-$machine"
mirror="https://dl-cdn.alpinelinux.org/alpine/$release/main/$machine"
mkdir -p "$cache"

if [ ! -f "$cache/APKINDEX" ]; then
	curl -sfL "$mirror/APKINDEX.tar.gz" -o "$cache/index.tar.gz"
	tar xzf "$cache/index.tar.gz" -C "$cache" APKINDEX
fi

version() {
	awk -v want="P:$1" '$0 == want { found = 1; next } found && /^V:/ { sub(/^V:/, ""); print; exit }' \
		"$cache/APKINDEX"
}

fetch() {
	local package="$1" version
	version="$(version "$package")"
	[ -n "$version" ] || { echo "fetch-jre: no $package in $release/$machine" >&2; exit 1; }

	local file="$cache/$package-$version.apk"
	[ -f "$file" ] || curl -sfL "$mirror/$package-$version.apk" -o "$file"

	rm -rf "$cache/unpacked/$package"
	mkdir -p "$cache/unpacked/$package"
	tar xzf "$file" -C "$cache/unpacked/$package" 2>/dev/null || true
}

# What a Temurin alpine JVM is linked against. zlib is the one gdbserver does
# not need and the JVM does — its absence shows up as a JVM that starts and
# then cannot open a single jar.
fetch musl
fetch libgcc
fetch libstdc++
fetch zlib

mkdir -p "$rootfs/lib" "$rootfs/usr/lib" "$rootfs/opt"
cp "$cache/unpacked/musl/lib/ld-musl-$machine.so.1" "$rootfs/lib/"
cp "$cache/unpacked/musl/lib/libc.musl-$machine.so.1" "$rootfs/lib/"
cp "$cache/unpacked/libgcc/usr/lib/libgcc_s.so.1" "$rootfs/usr/lib/"
cp "$(ls "$cache/unpacked/libstdc++/usr/lib/"libstdc++.so.6.* | head -1)" "$rootfs/usr/lib/libstdc++.so.6"
# zlib lives under /usr/lib in the package, and the .so.1 in it is a symlink —
# the real file is what has to be copied, under the name its users ask for.
cp "$(ls "$cache/unpacked/zlib/usr/lib/"libz.so.1.* | head -1)" "$rootfs/usr/lib/libz.so.1"

# The JRE rather than the JDK: this runs a jar that was built on the developer's
# machine, and shipping a compiler to a pod that never compiles is fifty
# megabytes nobody reads.
jre="$here/out/temurin-jre-$java-$adoptium.tar.gz"
if [ ! -f "$jre" ]; then
	url="https://api.adoptium.net/v3/binary/latest/$java/ga/alpine-linux/$adoptium/jre/hotspot/normal/eclipse"
	echo "  fetching a Java $java JRE for linux/$arch"
	curl -sfL "$url" -o "$jre"
fi

rm -rf "$rootfs/opt/java"
mkdir -p "$rootfs/opt/java"
tar xzf "$jre" -C "$rootfs/opt/java" --strip-components=1

# `java -version` is not run here: this JVM is for linux/$arch and the machine
# assembling the image usually is not. What is checked is that the file the
# supervisor will exec exists, which is the failure worth catching early.
[ -x "$rootfs/opt/java/bin/java" ] || {
	echo "fetch-jre: the archive had no bin/java in it" >&2
	exit 1
}

printf '  a Java %s JRE (%s) and four libraries\n' "$java" "$(du -sh "$rootfs/opt/java" | cut -f1)"
