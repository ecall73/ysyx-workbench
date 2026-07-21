#include <nterm.h>
#include <stdarg.h>
#include <stdlib.h>
#include <unistd.h>
#include <SDL.h>

char handle_key(SDL_Event *ev);

static void sh_printf(const char *format, ...) {
  static char buf[256] = {};
  va_list ap;
  va_start(ap, format);
  int len = vsnprintf(buf, 256, format, ap);
  va_end(ap);
  term->write(buf, len);
}

static void sh_banner() {
  sh_printf("Built-in Shell in NTerm (NJU Terminal)\n\n");
}

static void sh_prompt() {
  sh_printf("sh> ");
}

static void sh_handle_cmd(const char *cmd) {
  char *buf = strdup(cmd);
  char *argv[16];
  int argc = 0;
  for (char *arg = strtok(buf, " \n"); arg != NULL && argc < 15; arg = strtok(NULL, " \n")) {
    argv[argc ++] = arg;
  }
  argv[argc] = NULL;

  if (argc > 0 && strcmp(argv[0], "echo") == 0) {
    for (int i = 1; i < argc; i ++) {
      sh_printf("%s%s", i == 1 ? "" : " ", argv[i]);
    }
    sh_printf("\n");
  } else if (argc > 0) {
    execvp(argv[0], argv);
  }

  free(buf);
}

void builtin_sh_run() {
  setenv("PATH", "/bin", 0);
  sh_banner();
  sh_prompt();

  while (1) {
    SDL_Event ev;
    if (SDL_PollEvent(&ev)) {
      if (ev.type == SDL_KEYUP || ev.type == SDL_KEYDOWN) {
        const char *res = term->keypress(handle_key(&ev));
        if (res) {
          sh_handle_cmd(res);
          sh_prompt();
        }
      }
    }
    refresh_terminal();
  }
}
