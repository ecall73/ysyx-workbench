#include <am.h>
#include <NDL.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static int screen_w, screen_h;

#define NAME(key) [AM_KEY_##key] = #key,
static const char *keyname[] = {
  [AM_KEY_NONE] = "NONE",
  AM_KEYS(NAME)
};

static void read_keyboard(AM_INPUT_KEYBRD_T *kbd) {
  char event[64] = {};
  char action[3], key[16];

  kbd->keydown = false;
  kbd->keycode = AM_KEY_NONE;
  if (!NDL_PollEvent(event, sizeof(event)) ||
      sscanf(event, "%2s %15s", action, key) != 2) {
    return;
  }

  for (int i = 1; i < (int)(sizeof(keyname) / sizeof(keyname[0])); i++) {
    if (strcmp(key, keyname[i]) == 0) {
      kbd->keydown = strcmp(action, "kd") == 0;
      kbd->keycode = i;
      return;
    }
  }
}

bool ioe_init() {
  NDL_Init(0);
  NDL_OpenCanvas(&screen_w, &screen_h);
  return true;
}

void ioe_read(int reg, void *buf) {
  switch (reg) {
    case AM_TIMER_CONFIG:
      *(AM_TIMER_CONFIG_T *)buf = (AM_TIMER_CONFIG_T) { true, false };
      break;
    case AM_TIMER_UPTIME:
      ((AM_TIMER_UPTIME_T *)buf)->us = (uint64_t)NDL_GetTicks() * 1000;
      break;
    case AM_INPUT_CONFIG:
      ((AM_INPUT_CONFIG_T *)buf)->present = true;
      break;
    case AM_INPUT_KEYBRD:
      read_keyboard(buf);
      break;
    case AM_GPU_CONFIG:
      *(AM_GPU_CONFIG_T *)buf = (AM_GPU_CONFIG_T) {
        true, false, screen_w, screen_h, 0,
      };
      break;
    case AM_GPU_STATUS:
      ((AM_GPU_STATUS_T *)buf)->ready = true;
      break;
    default:
      assert(0);
  }
}

void ioe_write(int reg, void *buf) {
  if (reg == AM_GPU_FBDRAW) {
    AM_GPU_FBDRAW_T *ctl = buf;
    if (ctl->pixels != NULL) {
      NDL_DrawRect(ctl->pixels, ctl->x, ctl->y, ctl->w, ctl->h);
    }
    return;
  }
  assert(0);
}
