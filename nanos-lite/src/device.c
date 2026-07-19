#include <common.h>

#if defined(MULTIPROGRAM) && !defined(TIME_SHARING)
# define MULTIPROGRAM_YIELD() yield()
#else
# define MULTIPROGRAM_YIELD()
#endif

#define NAME(key) \
  [AM_KEY_##key] = #key,

static const char *keyname[256] __attribute__((used)) = {
  [AM_KEY_NONE] = "NONE",
  AM_KEYS(NAME)
};

size_t serial_write(const void *buf, size_t offset, size_t len) {
  for (size_t i = 0; i < len; i ++) {
    putch(((const char *)buf)[i]);
  }
  return len;
}

size_t events_read(void *buf, size_t offset, size_t len) {
  AM_INPUT_KEYBRD_T event = io_read(AM_INPUT_KEYBRD);
  if (event.keycode == AM_KEY_NONE) {
    return 0;
  }

  char event_text[64];
  int event_len = snprintf(event_text, sizeof(event_text), "k%c %s\n",
      event.keydown ? 'd' : 'u', keyname[event.keycode]);
  assert(event_len >= 0 && event_len < (int)sizeof(event_text));
  size_t nread = event_len;
  if (nread > len) {
    nread = len;
  }
  memcpy(buf, event_text, nread);
  return nread;
}

size_t dispinfo_read(void *buf, size_t offset, size_t len) {
  return 0;
}

size_t fb_write(const void *buf, size_t offset, size_t len) {
  return 0;
}

void init_device() {
  Log("Initializing devices...");
  ioe_init();
}
