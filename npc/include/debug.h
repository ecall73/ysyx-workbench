#ifndef __DEBUG_H__
#define __DEBUG_H__

#include <common.h>
#include <stdio.h>
#include <utils.h>

#ifdef __cplusplus
extern "C" {
#endif
void assert_fail_msg();
#ifdef __cplusplus
}
#endif

static inline const char *log_file_path(const char *file) {
  static char path[256];
  const char *p = strstr(file, "/npc/");
  if (p != NULL) return p + 1;

  p = strstr(file, "npc/");
  if (p != NULL) return p;

  p = strstr(file, "src/");
  if (p != NULL) {
    snprintf(path, sizeof(path), "npc/%s", p);
    return path;
  }
  return p != NULL ? p : file;
}

#define Log(format, ...) \
    _Log(ANSI_FMT("[%s:%d %s] " format, ANSI_FG_BLUE) "\n", \
        log_file_path(__FILE__), __LINE__, __func__, ## __VA_ARGS__)

#define Assert(cond, format, ...) \
  do { \
    if (!(cond)) { \
      fflush(stdout); \
      fprintf(stderr, ANSI_FMT(format, ANSI_FG_RED) "\n", ##  __VA_ARGS__); \
      extern FILE* log_fp; \
      fflush(log_fp); \
      assert_fail_msg(); \
      assert(cond); \
    } \
  } while (0)

#define panic(format, ...) Assert(0, format, ## __VA_ARGS__)

#endif
