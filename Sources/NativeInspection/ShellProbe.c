#include "ShellProbe.h"
#include <util.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <signal.h>
#include <errno.h>
#include <sys/wait.h>

struct PDShellProbe { pid_t pid; int fd; int finished; int code; };

PDShellProbe *pd_shell_start(char *const argv[], char *const envp[], const char *cwd) {
    PDShellProbe *probe = calloc(1, sizeof(*probe));
    if (!probe) return NULL;
    const int descriptor_limit = getdtablesize();
    struct winsize size = {.ws_row = 24, .ws_col = 100};
    probe->pid = forkpty(&probe->fd, NULL, NULL, &size);
    if (probe->pid == 0) {
        // Only async-signal-safe calls between fork and exec in a multi-threaded app.
        // Do not leak application files or sockets into user startup commands.
        for (int fd = 3; fd < descriptor_limit; ++fd) close(fd);
        if (chdir(cwd) != 0) _exit(126);
        execve("/bin/zsh", argv, envp);
        _exit(127);
    }
    if (probe->pid < 0) { free(probe); return NULL; }
    fcntl(probe->fd, F_SETFD, FD_CLOEXEC);
    int flags = fcntl(probe->fd, F_GETFL);
    if (flags < 0 || fcntl(probe->fd, F_SETFL, flags | O_NONBLOCK) < 0) {
        pd_shell_close(probe); return NULL;
    }
    return probe;
}

int pd_shell_read(PDShellProbe *probe, void *buffer, size_t capacity) {
    ssize_t count = read(probe->fd, buffer, capacity);
    return count > 0 ? (int)count : 0;
}

int pd_shell_status(PDShellProbe *probe, int *exit_code) {
    if (!probe->finished) {
        int status = 0;
        pid_t result = waitpid(probe->pid, &status, WNOHANG);
        if (result == probe->pid) {
            probe->finished = 1;
            probe->code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
        } else if (result < 0 && errno == ECHILD) {
            probe->finished = 1; probe->code = 255;
        }
    }
    *exit_code = probe->code;
    return probe->finished;
}

void pd_shell_close(PDShellProbe *probe) {
    if (!probe) return;
    if (!probe->finished) {
        // The child remains ours and unreaped, preventing PID reuse while signaling.
        kill(-probe->pid, SIGKILL);
        kill(probe->pid, SIGKILL);
        while (waitpid(probe->pid, NULL, 0) < 0 && errno == EINTR) {}
    }
    close(probe->fd);
    free(probe);
}
