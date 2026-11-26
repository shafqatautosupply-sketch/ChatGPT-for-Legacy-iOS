/*
 * sbtest.c - checks, on the device, what the agent's Seatbelt profile really enforces.
 * It applies the SAME profile AGSandbox builds (writes only in a work dir, no reads of the
 * home folder except that dir, no network, no Mach lookups) and probes it, including an
 * exec'd `rm -rf` and (optionally) python3. Run as the app's user (mobile), not root:
 *
 *     ./build.sh && ./sbtest [path-to-python3 [extra-readable-dir ...]]
 *
 * Measured on iOS 6.1.3 / iPhone 4s: all rows OK. Known NOT enforced by that kernel:
 * signals and ptrace between processes of the same user, process-exec rules, /var/tmp
 * (always readable and writable). See Docs/SECURITY.md.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#ifndef MOBILE
#define MOBILE "/private/var/mobile"
#endif
#define WORK     MOBILE "/.sbtest_work"
#define OWN      WORK "/own.txt"
#define VDIR     WORK "/vdir"
#define SEC      MOBILE "/.sbtest_secret"
#define OUTSIDE  MOBILE "/.sbtest_outside"
#define VICTIM   MOBILE "/.sbtest_victim"

typedef int (*sbinit_fn)(const char *, uint64_t, char **);
static sbinit_fn sb_init;
#ifdef HOST_STUB
static int stub_init(const char *p, uint64_t f, char **e) { (void)p; (void)f; if (e) *e = NULL; return 0; }
#endif
static int load_sb(void) {
#ifdef HOST_STUB
	sb_init = stub_init; return 1;
#else
	void *h = dlsym(RTLD_DEFAULT, "sandbox_init");
	if (!h) { void *l = dlopen("/usr/lib/libsandbox.1.dylib", RTLD_NOW); if (l) h = dlsym(l, "sandbox_init"); }
	sb_init = (sbinit_fn)h; return h != NULL;
#endif
}

static int denied(int e) { return e == EPERM || e == EACCES; }
static const char *word(int v) { return v == 1 ? "allowed" : v == 0 ? "BLOCKED" : "error"; }
static void wrap(const char *s) { size_t n = strlen(s), i; for (i = 0; i < n; i += 36) printf(" %.36s\n", s + i); }
static int exists(const char *p) { struct stat st; return stat(p, &st) == 0; }
static void touch(const char *p) { int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644); if (fd >= 0) { write(fd, "x\n", 2); close(fd); } }

static int rd(const char *p) {
	int fd = open(p, O_RDONLY); char b[2];
	if (fd >= 0) { int n = (int)read(fd, b, 1); close(fd); return n >= 0 ? 1 : 0; }
	return denied(errno) ? 0 : -1;
}
static int wr(const char *p) {
	int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd >= 0) { close(fd); unlink(p); return 1; }
	return denied(errno) ? 0 : -1;
}
static int net(void) {
	struct sockaddr_in a; int s = socket(AF_INET, SOCK_STREAM, 0), r, e;
	if (s < 0) return denied(errno) ? 0 : -1;
	memset(&a, 0, sizeof a); a.sin_family = AF_INET; a.sin_port = htons(9); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	r = connect(s, (struct sockaddr *)&a, sizeof a); e = errno; close(s);
	if (r == 0 || e == ECONNREFUSED) return 1;
	return denied(e) ? 0 : -1;
}
static int mach(void) {
#ifdef HOST_STUB
	return 1;
#else
	typedef int (*f_t)(unsigned, const char *, unsigned *);
	f_t f = (f_t)dlsym(RTLD_DEFAULT, "bootstrap_look_up");
	unsigned *bp = (unsigned *)dlsym(RTLD_DEFAULT, "bootstrap_port");
	unsigned p = 0;
	if (!f || !bp) return -1;
	return f(*bp, "com.apple.system.notification_center", &p) == 0 ? 1 : 0;
#endif
}

/* run path in a child: 0 = ran fine, 126 = exec blocked, other = ran but failed / not found */
static int run_exec(const char *path, const char *a1, const char *a2) {
	pid_t c; int st;
	c = fork();
	if (c == 0) {
		execl(path, path, a1, a2, (char *)NULL);
		_exit(denied(errno) ? 126 : 127);
	}
	waitpid(c, &st, 0);
	return WIFEXITED(st) ? WEXITSTATUS(st) : 99;
}

static const char *find_rm(void) {
	static const char *c[] = {"/bin/rm", "/usr/bin/rm", "/usr/local/bin/rm", NULL};
	int i; for (i = 0; c[i]; i++) if (exists(c[i])) return c[i];
	return NULL;
}
static int run_final(const char *prof, const char *py) {
	pid_t pid; int st;
	mkdir(VDIR, 0755); touch(VDIR "/f"); touch(VICTIM);
	fflush(stdout);
	pid = fork();
	if (pid == 0) {
		char *err = NULL; int v, bad = 0, r; const char *rm; pid_t c;
		if (sb_init(prof, 0, &err) != 0) { printf(" init FAIL\n"); wrap(err ? err : "?"); fflush(stdout); _exit(200); }
		chdir(WORK);
#define ROW(label, call, want) v = call; printf(" %-15s%-8s%s\n", label, word(v), v == want ? "OK" : "<-BAD"); if (v != want) bad++;
		ROW("write work", wr(WORK "/probe"), 1)
		ROW("read work", rd(OWN), 1)
		ROW("write outside", wr(OUTSIDE), 0)
		ROW("read secret", rd(SEC), 0)
		ROW("network", net(), 0)
		ROW("mach lookup", mach(), 0)
		v = sb_init("(version 1)(allow default)", 0, &err);
		printf(" relax rc=%d net:%s %s\n", v, word(net()), net() == 0 ? "OK" : "<-BAD"); if (net() != 0) bad++;

		rm = find_rm();
		if (rm) { c = fork(); if (c == 0) { execl(rm, "rm", "-rf", VICTIM, VDIR, (char *)NULL); _exit(127); } waitpid(c, &st, 0); }
		if (py) {
			r = run_exec(py, "-c", "print(2+2)");
			printf(" python exit=%d %s\n", r, r == 0 ? "OK" : "<-CHECK"); if (r != 0) bad++;
		}
		fflush(stdout); _exit(bad);
	}
	waitpid(pid, &st, 0);
	{ int alive = exists(VICTIM), gone = !exists(VDIR);
	  printf(" rm kept outside %s\n rm cleared work  %s\n", alive ? "OK" : "<-BAD", gone ? "OK" : "<-BAD"); }
	return WIFEXITED(st) ? WEXITSTATUS(st) : 99;
}

#define CAT(...) do { size_t n_ = strlen(prof); snprintf(prof + n_, sizeof prof - n_, __VA_ARGS__); } while (0)

int main(int argc, char **argv) {
	int i, k; static char prof[8192]; const char *py = argc > 1 ? argv[1] : NULL;
	printf("sbtest uid=%d\n", (int)getuid());
	if (geteuid() == 0) printf("WARNING: root! use mobile\n");
	if (!load_sb()) { printf("no sandbox_init\n"); return 2; }
	mkdir(WORK, 0755); touch(OWN); touch(SEC);

	prof[0] = 0;
	CAT("(version 1)(allow default)(deny network*)");
	CAT("(deny file-write*)(allow file-write* (subpath \"" WORK "\"))(allow file-write* (literal \"/dev/null\"))");
	CAT("(deny file-read* (subpath \"" MOBILE "\"))(allow file-read* (subpath \"" WORK "\"))");
	for (k = 2; k < argc; k++) CAT("(allow file-read* (subpath \"%s\"))", argv[k]);
	CAT("(deny mach-lookup)(deny mach-priv-task-port)");
	printf("\n== final profile test\n");
	i = run_final(prof, py);

	unlink(OWN); unlink(SEC); unlink(OUTSIDE); unlink(VICTIM); unlink(VDIR "/f"); rmdir(VDIR);
	unlink(WORK "/probe"); rmdir(WORK);
	printf("\n final: %s\n", i == 0 ? "ALL OK" : "has BAD rows");
	printf("\nprofile (%d bytes):\n", (int)strlen(prof)); wrap(prof);
	printf("\nPaste all of this back.\n");
	return 0;
}
