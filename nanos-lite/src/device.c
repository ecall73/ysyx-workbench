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

  return snprintf(buf, len, "k%c %s\n",
      event.keydown ? 'd' : 'u', keyname[event.keycode]);
}

size_t dispinfo_read(void *buf, size_t offset, size_t len) {
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  return snprintf(buf, len, "WIDTH:%d\nHEIGHT:%d\n", cfg.width, cfg.height);
}

size_t fb_write(const void *buf, size_t offset, size_t len) {
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  assert(offset % sizeof(uint32_t) == 0 && len % sizeof(uint32_t) == 0);
  size_t pixel_offset = offset / sizeof(uint32_t);
  io_write(AM_GPU_FBDRAW,
      .x = pixel_offset % cfg.width,
      .y = pixel_offset / cfg.width,
      .pixels = (void *)buf,
      .w = len / sizeof(uint32_t),
      .h = 1,
      .sync = true);
  return len;
}

void init_device() {
  Log("Initializing devices...");
  ioe_init();
}
