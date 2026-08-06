#!/usr/bin/env python3
"""Pins a Mach-O's LC_UUID, so a local build keeps its Local Network grant.

macOS files that grant against the executable's UUID rather than against the
bundle identifier alone: a rebuild changes the UUID, the association is gone,
and the app is denied — for itself and for everything it launches, which is
every debugger and every program under test. Normally the app would simply be
asked about again, but on macOS 27 beta nehelper refuses UserEventAgent the
connection that presents the prompt, so no new association can be made at all.

Pinning the UUID to one that is already associated is what keeps a build that
was compiled a minute ago able to reach the network. It is a workaround for a
machine and never for a release: identical UUIDs make crash reports ambiguous
about which build they came from, which is the whole reason the linker derives
it from content.
"""
import struct, sys, uuid

LC_UUID = 0x1B
MH_MAGIC_64 = 0xFEEDFACF


def pin(path: str, wanted: uuid.UUID) -> None:
    data = bytearray(open(path, "rb").read())
    (magic,) = struct.unpack_from("<I", data, 0)
    if magic != MH_MAGIC_64:
        raise SystemExit(f"{path}: not a 64-bit little-endian Mach-O ({magic:#x})")

    (ncmds,) = struct.unpack_from("<I", data, 16)
    offset = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, offset)
        if cmd == LC_UUID:
            was = uuid.UUID(bytes=bytes(data[offset + 8:offset + 24]))
            if was == wanted:
                print(f"    uuid already {wanted}")
                return
            data[offset + 8:offset + 24] = wanted.bytes
            open(path, "wb").write(data)
            print(f"    uuid {was} -> {wanted}")
            return
        offset += size
    raise SystemExit(f"{path}: no LC_UUID to pin")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: pin-uuid.py <mach-o> <uuid>")
    pin(sys.argv[1], uuid.UUID(sys.argv[2]))
