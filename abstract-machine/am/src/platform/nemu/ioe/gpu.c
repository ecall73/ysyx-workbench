#include <am.h>
#include <nemu.h>

#define SYNC_ADDR (VGACTL_ADDR + 4)

static int w = 0;
static int h = 0;

void __am_gpu_init() {
  ///*  PA2 输入输出 VGA 静态渐变测试
  //int i;
  uint32_t wh = inl(VGACTL_ADDR);
  w = wh >> 16;
  h = wh & 0xffff;
/*
  uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
  for (i = 0; i < w * h; i ++) fb[i] = i;
  outl(SYNC_ADDR, 1);
  */
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  *cfg = (AM_GPU_CONFIG_T) {
    .present = true, .has_accel = false,
    .width = w, .height = h,
    .vmemsz = 0
  };
}

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  if (ctl->pixels) {
    int x = ctl->x, y = ctl->y, draw_w = ctl->w, draw_h = ctl->h;
    uint32_t *pixels = (uint32_t *)ctl->pixels;
    uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;

    for (int j = 0; j < draw_h; j ++) {
      for (int i = 0; i < draw_w; i ++) {
        fb[(y + j) * w + (x + i)] = pixels[j * draw_w + i];
      }
    }
  }

  if (ctl->sync) {
    outl(SYNC_ADDR, 1);
  }
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = true;
}
