// Second instrument: separates "the child finished its work" from "the child
// finished exiting", because the first probe showed 600ms between the bytes
// arriving and the child becoming a zombie and could not say what that was.
//
// The child writes to the pty, then writes one byte down a pipe the parent
// holds, then _exit(0). So the pipe byte timestamps the last instruction the
// child runs in user space, and the zombie timestamp is the kernel finishing
// with it. No exec, so dyld is not in the picture.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <util.h>
#include <poll.h>
#include <termios.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/sysctl.h>

static double now_ms(void) {
	struct timeval tv; gettimeofday(&tv, NULL);
	return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

static int child_state(pid_t pid) {
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
	struct kinfo_proc info; size_t len = sizeof(info);
	if (sysctl(mib, 4, &info, &len, NULL, 0) != 0 || len == 0) return -1;
	return info.kp_proc.p_stat;
}
static const char *state_name(int s) {
	switch (s) {
	case -1: return "reaped/gone"; case SIDL: return "idle"; case SRUN: return "runnable";
	case SSLEEP: return "sleeping"; case SSTOP: return "STOPPED"; case SZOMB: return "zombie";
	default: return "?";
	}
}

int main(int argc, char **argv) {
	// hold: parent opens the slave.  bytes: how much the child writes.
	int hold = argc > 1 && strstr(argv[1], "hold") != NULL;
	int drain = argc > 1 && strstr(argv[1], "drain") != NULL;
	int bytes = argc > 2 ? atoi(argv[2]) : 15;
	double watch_ms = argc > 3 ? atof(argv[3]) : 3000.0;

	int marker[2];
	if (pipe(marker) != 0) { perror("pipe"); return 1; }

	int master = -1; char slave_path[128];
	pid_t pid = forkpty(&master, slave_path, NULL, NULL);
	if (pid < 0) { perror("forkpty"); return 1; }
	if (pid == 0) {
		close(marker[0]);
		char *payload = malloc(bytes + 1);
		memset(payload, 'x', bytes);
		payload[bytes - 1] = '\n';
		write(1, payload, bytes);
		write(marker[1], "d", 1);      // "done writing, about to exit"
		_exit(0);
	}
	close(marker[1]);
	double t0 = now_ms();
	fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);
	fcntl(marker[0], F_SETFL, O_NONBLOCK);

	int slave_held = -1;
	if (hold) slave_held = open(slave_path, O_RDWR | O_NOCTTY);

	double marker_ms = -1, zombie_ms = -1, drained_ms = -1;
	long drained = 0;
	int last_s = -2; short last_r = -1;
	for (;;) {
		double t = now_ms() - t0;
		if (t > watch_ms) break;
		if (zombie_ms >= 0 && t > zombie_ms + 300) break;

		char c;
		if (marker_ms < 0 && read(marker[0], &c, 1) == 1) {
			marker_ms = t;
			printf("  %7.2fms  child reached _exit\n", marker_ms);
		}
		struct pollfd p = { .fd = master, .events = POLLIN };
		poll(&p, 1, 0);
		if (drain) {
			char sink[4096]; ssize_t got;
			while ((got = read(master, sink, sizeof sink)) > 0) {
				drained += got;
				if (drained_ms < 0) { drained_ms = t; printf("  %7.2fms  parent read %zd bytes\n", t, got); }
			}
		}
		int s = child_state(pid);
		if (s == SZOMB && zombie_ms < 0) zombie_ms = t;
		if (p.revents != last_r || s != last_s) {
			printf("  %7.2fms  master:%s%s  child: %s\n", t,
			       (p.revents & POLLIN) ? " IN" : " --",
			       (p.revents & POLLHUP) ? " HUP" : "", state_name(s));
			last_r = p.revents; last_s = s;
		}
		usleep(300);
	}

	char buf[8192];
	ssize_t n = read(master, buf, sizeof buf);
	int e = errno;
	printf("%-12s bytes=%-6d child_exit=%.1fms zombie=%.1fms drained=%ld  READ n=%zd %s\n",
	       argc > 1 ? argv[1] : "plain", bytes, marker_ms, zombie_ms, drained, n,
	       n < 0 ? strerror(e) : (n == 0 ? "(eof)" : "(bytes)"));

	if (slave_held >= 0) close(slave_held);
	close(master);
	int st; waitpid(pid, &st, 0);
	return 0;
}
