#pragma once
#include <stddef.h>
#include <stdint.h>
// Owns a newly created diagnostic shell only. Never attach to existing processes.
typedef struct PDShellProbe PDShellProbe;
PDShellProbe *pd_shell_start(char *const argv[], char *const envp[], const char *cwd);
int pd_shell_read(PDShellProbe *probe, void *buffer, size_t capacity);
// 0 running, 1 exited; exit_code is normalized (128 + signal when signaled).
int pd_shell_status(PDShellProbe *probe, int *exit_code);
// Terminates only the unreaped diagnostic child and its original process group.
void pd_shell_close(PDShellProbe *probe);
