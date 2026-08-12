// The window between the child existing and the parent holding the child's end
// of the terminal, made deterministic. The parent simply sleeps for 700ms --
// past the pty's 600ms deadline -- where under load it would be descheduled.
//
//   late : forkpty, then reopen the slave by name afterwards (what forkpty
//          forces, because it closes the parent's slave before returning)
//   early: openpty, then fork, so the descriptor exists before the child does
//
// Neither reads the master until the very end, which is the condition a starved
// reading queue produces.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <util.h>
#include <sys/wait.h>

int main(int argc, char **argv) {
	int early = argc > 1 && strcmp(argv[1], "early") == 0;
	int stall_us = (argc > 2 ? atoi(argv[2]) : 700) * 1000;

	int master = -1, slave = -1;
	pid_t pid;

	if (early) {
		if (openpty(&master, &slave, NULL, NULL, NULL) != 0) { perror("openpty"); return 1; }
		pid = fork();
		if (pid == 0) {
			close(master);
			login_tty(slave);
			execl("/bin/echo", "echo", "hello-from-pty", (char *)NULL);
			_exit(127);
		}
	} else {
		pid = forkpty(&master, NULL, NULL, NULL);
		if (pid == 0) {
			execl("/bin/echo", "echo", "hello-from-pty", (char *)NULL);
			_exit(127);
		}
		// The window: the child is running and nothing on this side holds its end.
		usleep(stall_us);
		char name[128];
		if (ptsname_r(master, name, sizeof name) == 0) slave = open(name, O_RDWR | O_NOCTTY);
	}

	if (early) usleep(stall_us);   // the same stall, but after the descriptor exists

	fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);
	char buf[256];
	ssize_t n = read(master, buf, sizeof buf - 1);
	if (n > 0) { buf[n] = 0; for (char *p = buf; *p; p++) if (*p == '\r' || *p == '\n') *p = '.'; }

	printf("%-6s slave=%s stall=%dms -> %-22s %s\n",
	       early ? "early" : "late", slave >= 0 ? "held" : "not held", stall_us / 1000,
	       n > 0 ? buf : (n == 0 ? "NOTHING (eof)" : "NOTHING"),
	       n > 0 ? "SURVIVED" : "LOST");

	if (slave >= 0) close(slave);
	close(master);
	int st; waitpid(pid, &st, 0);
	return 0;
}
