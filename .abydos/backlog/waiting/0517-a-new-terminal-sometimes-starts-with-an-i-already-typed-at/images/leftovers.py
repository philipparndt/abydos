#!/usr/bin/env python3
"""Item 0517. What does a shell that never asked for it do with a sequence the
terminal writes into its pty?

Three experiments, none of which needs the app:

    python3 leftovers.py table    what each sequence leaves at a ready prompt
    python3 leftovers.py timing   the focus report at seven arrival times,
                                  from before the shell has exec'd onwards
    python3 leftovers.py tmux     the same through tmux, with the pane's own
                                  mode 1004 off and on

`table` is the one worth keeping. It opens a pty, exec's this machine's login
shell in it with its real configuration, writes the sequence at a settled
prompt, presses Return, and reads back whatever the shell complained it could
not run — which is exactly the debris the sequence left on the command line.
"""
import fcntl, os, pty, re, select, shutil, struct, subprocess, sys, termios, time

SEQS = [
	("focus in        CSI I",      b"\x1b[I"),
	("focus out       CSI O",      b"\x1b[O"),
	("kitty graphics  APC G",      b"\x1b_Gi=31;OK\x1b\\"),
	("open reply      OSC 440",    b"\x1b]440;abydos\x1b\\"),
	("primary DA",                 b"\x1b[?62;1;6;22c"),
	("secondary DA",               b"\x1b[>0;95;0c"),
	("device status",              b"\x1b[0n"),
	("text area pixels",           b"\x1b[4;480;800t"),
	("cell pixels",                b"\x1b[6;19;8t"),
	("text area cells",            b"\x1b[8;24;80t"),
	("mode report    DECRPM",      b"\x1b[?1004;1$y"),
	("kitty keyboard flags",       b"\x1b[?0u"),
	("cursor position",            b"\x1b[12;40R"),
	("bracketed paste wrapper",    b"\x1b[200~x\x1b[201~"),
	("SGR mouse press",            b"\x1b[<0;12;5M"),
	("legacy mouse press",         b"\x1b[M i5"),
	# The only two inputs that leave a lone lowercase `i`. Nothing this app
	# writes into a pty is either of them.
	("media copy    CSI 4 i",      b"\x1b[4i"),
	("a bare i",                   b"i"),
]


def drain(fd, seconds, out):
	end = time.time() + seconds
	while time.time() < end:
		ready, _, _ = select.select([fd], [], [], 0.05)
		if not ready:
			continue
		try:
			chunk = os.read(fd, 65536)
		except OSError:
			return False
		if not chunk:
			return False
		out += chunk
	return True


def spawn(shell=None, args=None, rows=24, columns=200):
	shell = shell or os.environ.get("SHELL", "/bin/zsh")
	args = args if args is not None else [shell, "-l"]
	pid, fd = pty.fork()
	if pid == 0:
		os.environ["TERM"] = "xterm-256color"
		os.execv(shell, args)
		os._exit(1)
	fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
	return pid, fd


def reap(pid, fd):
	try:
		os.close(fd)
	except OSError:
		pass
	try:
		os.waitpid(pid, 0)
	except ChildProcessError:
		pass


def probe(seq, **kwargs):
	"""Writes the sequence at a settled prompt and returns what followed."""
	pid, fd = spawn(**kwargs)
	out = bytearray()
	drain(fd, 2.0, out)
	mark = len(out)
	os.write(fd, seq)
	drain(fd, 0.4, out)
	os.write(fd, b"\r")
	drain(fd, 1.2, out)
	try:
		os.write(fd, b"\x04\x04")
	except OSError:
		pass
	drain(fd, 0.4, out)
	reap(pid, fd)
	return bytes(out[mark:])


def left(tail):
	found = re.findall(r"(?:command not found|not found):?\s*(.*)", tail)
	found = [f.strip() for f in found if f.strip()]
	return found or "nothing"


def table():
	for label, seq in SEQS:
		print(f"{label:30s} {seq!r:34s} -> left {left(probe(seq).decode('utf8', 'replace'))}")
		sys.stdout.flush()


def timing():
	"""The lead's own claim: the report arriving before the line editor is up."""
	for name, seq in (("control", b""), ("focus in", b"\x1b[I"), ("focus out", b"\x1b[O")):
		for delay in (0.0, 0.02, 0.05, 0.1, 0.2, 0.4, 0.8):
			pid, fd = spawn()
			out = bytearray()
			start = time.time()
			# Written before the shell has exec'd when the delay is zero, which
			# is the canonical-mode-with-echo state the lead names.
			while time.time() - start < delay:
				drain(fd, 0.02, out)
			if seq:
				os.write(fd, seq)
			drain(fd, 2.0, out)
			os.write(fd, b"echo MARK\r")
			drain(fd, 1.2, out)
			text = out.decode("utf8", "replace")
			index = text.rfind("echo MARK")
			window = text[max(0, index - 40):index + 12] if index >= 0 else text[-80:]
			reap(pid, fd)
			print(f"{name:10s} delay={delay:.2f} left={left(text)} …{window!r}")
			sys.stdout.flush()


def through_tmux():
	tmux = shutil.which("tmux")
	sock = "abydos0517"
	for name, seq in (("focus in", b"\x1b[I"), ("focus out", b"\x1b[O")):
		for enabled in (False, True):
			subprocess.run([tmux, "-L", sock, "kill-server"],
			               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
			time.sleep(0.2)
			pid, fd = spawn(shell=tmux, args=[tmux, "-L", sock, "new", "-A", "-s", "t"])
			out = bytearray()
			drain(fd, 1.5, out)
			if enabled:
				# What a program that asked for focus events and then died
				# leaves behind: the pane's mode, with a shell in front of it.
				os.write(fd, b"printf '\\033[?1004h'\r")
				drain(fd, 0.8, out)
			os.write(fd, seq)
			drain(fd, 0.5, out)
			os.write(fd, b"echo MARK\r")
			drain(fd, 1.5, out)
			pane = subprocess.run([tmux, "-L", sock, "capture-pane", "-p", "-t", "t"],
			                      capture_output=True, text=True).stdout
			reap(pid, fd)
			subprocess.run([tmux, "-L", sock, "kill-server"],
			               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
			lines = [line for line in pane.splitlines() if line.strip()]
			print(f"{name:10s} pane 1004={enabled} -> {lines[-3:]}")
			sys.stdout.flush()


if __name__ == "__main__":
	which = sys.argv[1] if len(sys.argv) > 1 else "table"
	{"table": table, "timing": timing, "tmux": through_tmux}[which]()
