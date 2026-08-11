#!/usr/bin/env python3
"""Run icat under a pty with no TMUX, answering its graphics queries the way
AbydosKit's TerminalImageStore.decode does:

  t=d (direct)         -> OK
  t=t (temporary file)  -> OK, and the file is deleted after reading
  t=s (shared memory)   -> EBADF:shared memory transfer is not supported

Set ABYDOS_SHM=ok to answer OK to shared memory instead, or ABYDOS_TEMP=bad to
refuse the temporary file, so the two can be told apart.

    icat_answer.py <rows> <cols> <cellw> <cellh> <out> <cmd...>
"""
import os, pty, sys, fcntl, termios, struct, select, re, base64

rows, cols, cellw, cellh = (int(x) for x in sys.argv[1:5])
out = sys.argv[5]
cmd = sys.argv[6:]

shm_ok = os.environ.get("ABYDOS_SHM") == "ok"
temp_ok = os.environ.get("ABYDOS_TEMP") != "bad"

env = dict(os.environ)
for key in ("TMUX", "TMUX_PANE"):
    env.pop(key, None)
env["TERM"] = "xterm-kitty"
env["COLUMNS"] = str(cols)
env["LINES"] = str(rows)

pid, fd = pty.fork()
if pid == 0:
    os.execvpe(cmd[0], cmd, env)

fcntl.ioctl(fd, termios.TIOCSWINSZ,
            struct.pack("HHHH", rows, cols, cols * cellw, rows * cellh))

data = bytearray()
pending = bytearray()
log = []

APC = re.compile(rb"\x1b_G([^;\x1b]*);?([^\x1b]*)\x1b\\")


def answer(control, payload):
    keys = {}
    for field in control.split(b","):
        if b"=" in field:
            k, v = field.split(b"=", 1)
            keys[k.decode()] = v.decode()
    if keys.get("a") != "q":
        return None
    ident = keys.get("i", "0")
    medium = keys.get("t", "d")
    verdict = "OK"
    if medium == "s":
        verdict = "OK" if shm_ok else "EBADF:shared memory transfer is not supported"
    elif medium in ("t", "f"):
        path = base64.b64decode(payload + b"=" * (-len(payload) % 4)).decode()
        try:
            with open(path, "rb") as handle:
                body = handle.read(int(keys.get("S", 0)) or None)
            log.append(f"  probe {medium}: {path} -> {len(body)} bytes {body!r}")
            expected = int(keys.get("s", 0)) * int(keys.get("v", 0)) * \
                (3 if keys.get("f") == "24" else 4)
            if len(body) != expected:
                verdict = f"EINVAL:{len(body)} bytes is not {keys.get('s')}x{keys.get('v')}"
            if medium == "t":
                os.unlink(path)
        except OSError as error:
            log.append(f"  probe {medium}: {path} -> {error}")
            verdict = f"EBADF:cannot read {path}"
        if not temp_ok:
            verdict = f"EBADF:cannot read {path}"
    log.append(f"  answer i={ident} t={medium} -> {verdict}")
    return b"\x1b_Gi=" + ident.encode() + b";" + verdict.encode() + b"\x1b\\"


while True:
    r, _, _ = select.select([fd], [], [], 15)
    if not r:
        break
    try:
        chunk = os.read(fd, 65536)
    except OSError:
        break
    if not chunk:
        break
    data += chunk
    pending += chunk

    reply = bytearray()
    while True:
        match = APC.search(bytes(pending))
        if not match:
            break
        got = answer(match.group(1), match.group(2))
        if got:
            reply += got
        del pending[: match.end()]
    # A primary device attributes request: icat uses it as a sync point.
    while b"\x1b[c" in pending:
        pending = bytearray(bytes(pending).replace(b"\x1b[c", b"", 1))
        reply += b"\x1b[?62;c"
    if reply:
        os.write(fd, bytes(reply))

os.waitpid(pid, 0)
with open(out, "wb") as handle:
    handle.write(bytes(data))
print("\n".join(log))
print(f"{len(data)} bytes -> {out}")
