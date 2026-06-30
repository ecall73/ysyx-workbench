#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "common.h"

#ifndef ITRACE_COND
#define ITRACE_COND true
#endif

#ifndef MTRACE_COND
#define MTRACE_COND true
#endif

FILE *npc_open_trace_log(const char *log_file, const char *name);

static FILE *ftrace_fp = NULL;
static FILE *etrace_fp = NULL;
static FILE *mtrace_fp = NULL;
static FILE *dtrace_fp = NULL;

static bool trace_window_enabled() {
#ifdef CONFIG_TRACE
    return g_nr_guest_inst >= CONFIG_TRACE_START && g_nr_guest_inst <= CONFIG_TRACE_END;
#else
    return false;
#endif
}

bool npc_trace_enabled() {
    return trace_window_enabled();
}

static void trace_vwrite(FILE *fp, const char *tag, const char *fmt, va_list ap) {
    if (!trace_window_enabled()) {
        return;
    }

    if (log_fp != NULL) {
        fprintf(log_fp, "[%s] ", tag);
        va_list log_ap;
        va_copy(log_ap, ap);
        vfprintf(log_fp, fmt, log_ap);
        fflush(log_fp);
        va_end(log_ap);
    }

    if (fp != NULL && fp != log_fp) {
        fprintf(fp, "[%s] ", tag);
        vfprintf(fp, fmt, ap);
        fflush(fp);
    }
}

static void close_trace_log(FILE **fp) {
    if (*fp != NULL) {
        fclose(*fp);
        *fp = NULL;
    }
}

void init_ftrace_log(const char *log_file) {
    ftrace_fp = npc_open_trace_log(log_file, "ftrace");
}

void init_etrace_log(const char *log_file) {
    etrace_fp = npc_open_trace_log(log_file, "etrace");
}

void init_mtrace_log(const char *log_file) {
    mtrace_fp = npc_open_trace_log(log_file, "mtrace");
}

void init_dtrace_log(const char *log_file) {
    dtrace_fp = npc_open_trace_log(log_file, "dtrace");
}

void close_trace_logs() {
    close_trace_log(&ftrace_fp);
    close_trace_log(&etrace_fp);
    close_trace_log(&mtrace_fp);
    close_trace_log(&dtrace_fp);
}

void itrace_write(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    trace_vwrite(NULL, "ITRACE", fmt, ap);
    va_end(ap);
}

void ftrace_write(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    trace_vwrite(ftrace_fp, "FTRACE", fmt, ap);
    va_end(ap);
}

void etrace_write(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    trace_vwrite(etrace_fp, "ETRACE", fmt, ap);
    va_end(ap);
}

void mtrace_write(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    trace_vwrite(mtrace_fp, "MTRACE", fmt, ap);
    va_end(ap);
}

void dtrace_write(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    trace_vwrite(dtrace_fp, "DTRACE", fmt, ap);
    va_end(ap);
}

static int access_len_from_size(int size) {
    return 1 << (size & 0x3);
}

extern "C" void npc_trace_read(int addr, int size, int data) {
#ifdef CONFIG_MTRACE
    if ((MTRACE_COND)) {
        int len = access_len_from_size(size);
        mtrace_write("R 0x%08x len=%d data=0x%08x\n", (uint32_t)addr, len, (uint32_t)data);
    }
#else
    (void)size;
    (void)data;
#endif

#ifdef CONFIG_DTRACE
    const char *dev = platform_device_name((uint32_t)addr);
    if (dev != NULL) {
        dtrace_write("%s R 0x%08x data=0x%08x\n", dev, (uint32_t)addr, (uint32_t)data);
    }
#else
    (void)addr;
#endif
}

extern "C" void npc_trace_write(int addr, int size, int data, int wstrb) {
#ifdef CONFIG_MTRACE
    if ((MTRACE_COND)) {
        int len = access_len_from_size(size);
        mtrace_write("W 0x%08x len=%d data=0x%08x mask=0x%x\n",
            (uint32_t)addr, len, (uint32_t)data, (uint8_t)wstrb);
    }
#else
    (void)size;
    (void)wstrb;
#endif

#ifdef CONFIG_DTRACE
    const char *dev = platform_device_name((uint32_t)addr);
    if (dev != NULL) {
        dtrace_write("%s W 0x%08x data=0x%08x mask=0x%x\n",
            dev, (uint32_t)addr, (uint32_t)data, (uint8_t)wstrb);
    }
#else
    (void)addr;
    (void)data;
#endif
}

extern "C" void npc_trace_ecall(int pc, int target, int mstatus, int mepc, int mcause) {
#ifdef CONFIG_ETRACE
    etrace_write("ecall pc=0x%08x -> 0x%08x mstatus=0x%08x mepc=0x%08x mcause=0x%08x\n",
        (uint32_t)pc, (uint32_t)target, (uint32_t)mstatus, (uint32_t)mepc, (uint32_t)mcause);
#else
    (void)pc;
    (void)target;
    (void)mstatus;
    (void)mepc;
    (void)mcause;
#endif
}

extern "C" void npc_trace_mret(int pc, int target, int mstatus, int mepc, int mcause) {
#ifdef CONFIG_ETRACE
    etrace_write("mret pc=0x%08x -> 0x%08x mstatus=0x%08x mepc=0x%08x mcause=0x%08x\n",
        (uint32_t)pc, (uint32_t)target, (uint32_t)mstatus, (uint32_t)mepc, (uint32_t)mcause);
#else
    (void)pc;
    (void)target;
    (void)mstatus;
    (void)mepc;
    (void)mcause;
#endif
}
