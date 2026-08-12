// Fourth instrument: the lifecycle questions the fix depends on.
//
//  1. With a slave held and nothing reading, the child cannot finish exiting.
//     Does closing the MASTER release it, or does it stay blocked for ever?
//     (This is what terminate() must be able to do.)
//  2. With a slave held, does a read on the master still reach EOF once the
//     child is really gone — or does the reader wait for ever?
//  3. Is the child reaped and the descriptor released, or left a zombie?

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <util.h>
#include <poll.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/sysctl.h>

static double now_ms(void) {
	struct timeval tv; gettimeofday(&tv, NULL);
	return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}
static int alive(pid_t pid) {
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
	struct kinfo_proc info; size_t len = sizeof info;
	if (sysctl(mib, 4, &info, &len, NULL, 0) != 0 || len == 0) return -1;
	return info.kp_proc.p_stat;
}

// scenario: "close-master" | "drain-then-eof" | "close-slave"
int main(int argc, char **argv) {
	const char *scenario = argc > 1 ? argv[1] : "close-master";

	int master = -1; char slave_path[128];
	pid_t pid = forkpty(&master, slave_path, NULL, NULL);
	if (pid < 0) return 1;
	// The child waits before writing, so the parent's open of the slave is
	// certainly first. In the app the child has to exec a binary, which takes
	// milliseconds, so this is the realistic ordering and not a convenience.
	if (pid == 0) { usleep(30000); write(1, "hello-from-pty\n", 15); _exit(0); }

	double t0 = now_ms();
	fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);
	int slave_held = open(slave_path, O_RDWR | O_NOCTTY);
	printf("[%s] slave held as fd %d\n", scenario, slave_held);

	// Let the child get well past its write and into the kernel's exit path.
	while (now_ms() - t0 < 800) usleep(500);
	printf("  %7.1fms  child state after 800ms with nobody reading: %d (2=run 5=zomb)\n",
	       now_ms() - t0, alive(pid));

	if (strcmp(scenario, "close-master") == 0) {
		close(master); master = -1;
		printf("  %7.1fms  closed the master\n", now_ms() - t0);
	} else if (strcmp(scenario, "close-slave") == 0) {
		close(slave_held); slave_held = -1;
		printf("  %7.1fms  closed the held slave\n", now_ms() - t0);
	} else {
		char buf[256];
		ssize_t n = read(master, buf, sizeof buf);
		printf("  %7.1fms  drained %zd bytes\n", now_ms() - t0, n);
	}

	// Does the child now finish?
	double waited = now_ms();
	int st = 0; pid_t r;
	while ((r = waitpid(pid, &st, WNOHANG)) == 0 && now_ms() - waited < 3000) usleep(500);
	printf("  %7.1fms  waitpid -> %d (%s) after %.1fms\n", now_ms() - t0, r,
	       r == pid ? "reaped" : "STILL BLOCKED", now_ms() - waited);

	// And does a reader on the master reach EOF?
	if (master >= 0) {
		double e0 = now_ms(); int sawEOF = 0; long got = 0;
		while (now_ms() - e0 < 2000) {
			char buf[256]; ssize_t n = read(master, buf, sizeof buf);
			if (n > 0) { got += n; continue; }
			if (n == 0) { sawEOF = 1; break; }
			if (errno != EAGAIN) { printf("  read errno=%d %s\n", errno, strerror(errno)); sawEOF = 1; break; }
			usleep(500);
		}
		printf("  %7.1fms  reader: %ld bytes then %s\n", now_ms() - t0, got,
		       sawEOF ? "EOF" : "NO EOF after 2s");
	}

	if (slave_held >= 0) close(slave_held);
	if (master >= 0) close(master);
	return 0;
}
