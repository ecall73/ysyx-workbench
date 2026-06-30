#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "common.h"

const char *npc_log_file(const char *file) {
    // Keep file prefix concise, similar to NEMU's src-relative style.
    const char *anchor = strstr(file, "/npc/");
    if (anchor != NULL) {
        return anchor + 5;  // strip "/npc/"
    }
    return file;
}

void _Log(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);

    if (log_fp != NULL && log_fp != stdout) {
        va_start(ap, fmt);
        vfprintf(log_fp, fmt, ap);
        fflush(log_fp);
        va_end(ap);
    }
}

void init_log(const char *log_file) {
    log_fp = NULL;
    if (log_file != NULL) {
        FILE *fp = fopen(log_file, "w");
        if (fp == NULL) {
            printf("Failed to open log file %s\n", log_file);
            return;
        }
        log_fp = fp;
    }
    Log("Log is written to %s", log_file ? log_file : "stdout");
}
