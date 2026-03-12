#include <am.h>
#include <nemu.h>

#define SYNC_ADDR   (VGACTL_ADDR + 4)

void __am_gpu_init() {
  int i;
  uint32_t size = inl(VGACTL_ADDR);
  int w = size >> 16;
  int h = size & 0xffff;
  uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
  for (i = 0; i < w * h; i ++) fb[i] = i;
  outl(SYNC_ADDR, 1);
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
  uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
  uint32_t *pixels = (uint32_t *)ctl->pixels;

  for (int j = 0; j < ctl->h; j++) {
    for (int i = 0; i < ctl->w; i++) {
      fb[(ctl->y + j) * screen_w + (ctl->x + i)] = pixels[j * ctl->w + i];
    }
  }

  if (ctl->sync) {
    outl(SYNC_ADDR, 1);
  }
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = true;
}
