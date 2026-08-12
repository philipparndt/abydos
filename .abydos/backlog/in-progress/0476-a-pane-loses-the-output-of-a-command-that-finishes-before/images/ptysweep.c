// Third instrument: read the master exactly N ms after the child wrote and
// exited, and say whether the bytes are still there. Sweeping N locates the
// deadline the kernel gives an unread pty, as a number rather than a story.
//
// With -hold, the parent keeps a descriptor on the slave for the whole wait.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <util.h>
#include <sys/wait.h>
#include <sys/time.h>

static double now_ms(void) {
	struct timeval tv; gettimeofday(&tv, NULL);
	return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

int main(int argc, char **argv) {
	double delay = argc > 1 ? atof(argv[1]) : 100;
	int hold = argc > 2 && strcmp(argv[2], "hold") == 0;

	int marker[2]; if (pipe(marker)) return 1;
	int master = -1; char slave_path[128];
	pid_t pid = forkpty(&master, slave_path, NULL, NULL);
	if (pid < 0) return 1;
	if (pid == 0) {
		close(marker[0]);
		write(1, "hello-from-pty\n", 15);
		write(marker[1], "d", 1);
		_exit(0);
	}
	close(marker[1]);
	fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);
	int slave_held = hold ? open(slave_path, O_RDWR | O_NOCTTY) : -1;

	// Wait for the child to have finished writing, so the delay is measured
	// from a known moment and not from the fork.
	char c; read(marker[0], &c, 1);
	double t0 = now_ms();
	while (now_ms() - t0 < delay) usleep(500);

	char buf[256];
	ssize_t n = read(master, buf, sizeof buf - 1);
	printf("delay=%-7.0fms hold=%d  ->  %s\n", delay, hold,
	       n > 0 ? "bytes" : (n == 0 ? "LOST (eof)" : strerror(errno)));

	if (slave_held >= 0) close(slave_held);
	close(master);
	int st; waitpid(pid, &st, 0);
	return 0;
}
