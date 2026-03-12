#include <am.h>
#include <nemu.h>

#define SYNC_ADDR   (VGACTL_ADDR + 4)

void __am_gpu_init() {
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  uint32_t size = inl(VGACTL_ADDR);
  cfg->width = size >> 16;
  cfg->height = size & 0xffff;
  cfg->vmemsz = cfg->width * cfg->height * sizeof(uint32_t);
  cfg->present = true;
  cfg->has_accel = false;
}

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  uint32_t size = inl(VGACTL_ADDR);
  int screen_w = size >> 16;
  int screen_h = size & 0xffff;
  uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
  uint32_t *pixels = (uint32_t *)ctl->pixels;

  for (int j = 0; j < ctl->h; j++) {
    int y = ctl->y + j;
    if (y < 0 || y >= screen_h) continue;

    for (int i = 0; i < ctl->w; i++) {
      int x = ctl->x + i;
      if (x < 0 || x >= screen_w) continue;
      fb[y * screen_w + x] = pixels[j * ctl->w + i];
    }
  }

  if (ctl->sync) {
    outl(SYNC_ADDR, 1);
  }
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = true;
}
