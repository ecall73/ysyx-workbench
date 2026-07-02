#include <ioe_diag.h>

static uint32_t row[640];

static void draw_row_pattern(int y, int w, int h) {
  for (int x = 0; x < w; x++) {
    bool border = x < 8 || y < 8 || x >= w - 8 || y >= h - 8;
    bool cross = (x >= w / 2 - 3 && x <= w / 2 + 3)
              || (y >= h / 2 - 3 && y <= h / 2 + 3);
    bool checker = ((x / 32) ^ (y / 32)) & 1;
    uint8_t grad = (uint8_t)((x * 255) / (w > 1 ? w - 1 : 1));

    row[x] = border ? diag_rgb(255, 255, 255)
           : cross ? diag_rgb(255, 0, 0)
           : y < 48 ? diag_rgb(grad, 255 - grad, 80)
           : checker ? diag_rgb(0, 160, 255)
           : diag_rgb(20, 20, 20);
  }
}

static void draw_block(int x, int y, int w, int h, uint32_t color, bool sync) {
  for (int i = 0; i < w; i++) row[i] = color;
  for (int j = 0; j < h; j++) {
    io_write(AM_GPU_FBDRAW, x, y + j, row, w, 1, sync && j == h - 1);
  }
}

int main(const char *args) {
  (void)args;
  ioe_init();

  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  AM_INPUT_CONFIG_T icfg = io_read(AM_INPUT_CONFIG);
  printf("[gpu-pattern][CONFIG] present=%d accel=%d width=%d height=%d vmemsz=%d input.present=%d\n",
      cfg.present, cfg.has_accel, cfg.width, cfg.height, cfg.vmemsz, icfg.present);
  if (!cfg.present || cfg.width <= 0 || cfg.height <= 0 || cfg.width > (int)LENGTH(row)) {
    printf("[gpu-pattern][FAIL] invalid GPU config\n");
    return 1;
  }

  printf("[gpu-pattern][EXPECT] white border, red center cross, top gradient, blue/dark checkerboard, four color corner blocks\n");
  for (int y = 0; y < cfg.height; y++) {
    draw_row_pattern(y, cfg.width, cfg.height);
    io_write(AM_GPU_FBDRAW, 0, y, row, cfg.width, 1, y == cfg.height - 1);
  }

  int bw = cfg.width / 8;
  int bh = cfg.height / 8;
  if (bw < 16) bw = 16;
  if (bh < 16) bh = 16;
  draw_block(16, 16, bw, bh, diag_rgb(255, 0, 0), false);
  draw_block(cfg.width - 16 - bw, 16, bw, bh, diag_rgb(0, 255, 0), false);
  draw_block(16, cfg.height - 16 - bh, bw, bh, diag_rgb(0, 0, 255), false);
  draw_block(cfg.width - 16 - bw, cfg.height - 16 - bh, bw, bh, diag_rgb(255, 255, 0), true);

  printf("[gpu-pattern][WAIT] press Esc to exit if keyboard is present\n");
  while (icfg.present) {
    if (diag_poll_exit()) break;
  }
  printf("[gpu-pattern][DONE]\n");
  return 0;
}
