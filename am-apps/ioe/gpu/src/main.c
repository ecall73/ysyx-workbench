#include <ioe_diag.h>

static uint32_t row[640];

static void fill_row(uint32_t color, int w) {
  for (int x = 0; x < w; x++) row[x] = color;
}

static void draw_rect(int x, int y, int w, int h, uint32_t color, bool sync) {
  fill_row(color, w);
  for (int j = 0; j < h; j++) {
    io_write(AM_GPU_FBDRAW, x, y + j, row, w, 1, sync && j == h - 1);
  }
}

static void draw_background(int w, int h, bool sync) {
  fill_row(diag_rgb(20, 20, 20), w);
  for (int y = 0; y < h; y++) {
    io_write(AM_GPU_FBDRAW, 0, y, row, w, 1, sync && y == h - 1);
  }
}

static void draw_border(int w, int h, bool sync) {
  draw_rect(0, 0, w, 8, diag_rgb(255, 255, 255), false);
  draw_rect(0, h - 8, w, 8, diag_rgb(255, 255, 255), false);
  draw_rect(0, 0, 8, h, diag_rgb(255, 255, 255), false);
  draw_rect(w - 8, 0, 8, h, diag_rgb(255, 255, 255), sync);
}

static void draw_gradient_band(int w, bool sync) {
  for (int y = 8; y < 48; y++) {
    for (int x = 8; x < w - 8; x++) {
      uint8_t grad = (uint8_t)((x * 255) / (w > 1 ? w - 1 : 1));
      row[x - 8] = diag_rgb(grad, 255 - grad, 80);
    }
    io_write(AM_GPU_FBDRAW, 8, y, row, w - 16, 1, sync && y == 47);
  }
}

static void draw_checkerboard(int w, int h, bool sync) {
  for (int y = 56; y < h - 8; y++) {
    for (int x = 8; x < w - 8; x++) {
      bool checker = ((x / 32) ^ (y / 32)) & 1;
      row[x - 8] = checker ? diag_rgb(0, 160, 255) : diag_rgb(20, 20, 20);
    }
    io_write(AM_GPU_FBDRAW, 8, y, row, w - 16, 1, sync && y == h - 9);
  }
}

static void draw_cross(int w, int h, bool sync) {
  draw_rect(w / 2 - 3, 8, 7, h - 16, diag_rgb(255, 0, 0), false);
  draw_rect(8, h / 2 - 3, w - 16, 7, diag_rgb(255, 0, 0), sync);
}

static void draw_corner_blocks(int w, int h, bool sync) {
  int bw = w / 8;
  int bh = h / 8;
  if (bw < 16) bw = 16;
  if (bh < 16) bh = 16;

  draw_rect(16, 16, bw, bh, diag_rgb(255, 0, 0), false);
  draw_rect(w - 16 - bw, 16, bw, bh, diag_rgb(0, 255, 0), false);
  draw_rect(16, h - 16 - bh, bw, bh, diag_rgb(0, 0, 255), false);
  draw_rect(w - 16 - bw, h - 16 - bh, bw, bh, diag_rgb(255, 255, 0), sync);
}

static bool step_wait(const char *step, const char *expect) {
  printf("[gpu][STEP %s] %s\n", step, expect);
  printf("[gpu][REFERENCE] am-apps/ioe/gpu/reference/%s.png\n", step);
  for (int i = 0; i < 120; i++) {
    if (diag_poll_exit()) return true;
    diag_delay(50000u);
  }
  return false;
}

int main(const char *args) {
  (void)args;
  ioe_init();

  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  AM_INPUT_CONFIG_T icfg = io_read(AM_INPUT_CONFIG);
  printf("[gpu][CONFIG] present=%d accel=%d width=%d height=%d vmemsz=%d input.present=%d\n",
      cfg.present, cfg.has_accel, cfg.width, cfg.height, cfg.vmemsz, icfg.present);
  if (!cfg.present || cfg.width <= 0 || cfg.height <= 0 || cfg.width > (int)LENGTH(row)) {
    printf("[gpu][FAIL] invalid GPU config\n");
    return 1;
  }

  printf("[gpu][EXPECT] staged draw; compare each step with am-apps/ioe/gpu/reference/*.png; Esc exits during waits\n");

  draw_background(cfg.width, cfg.height, true);
  if (step_wait("01-background", "full dark background; checks full-screen draw size")) goto done;

  draw_border(cfg.width, cfg.height, true);
  if (step_wait("02-border", "8-pixel white border; checks thin horizontal/vertical rectangles")) goto done;

  draw_gradient_band(cfg.width, true);
  if (step_wait("03-gradient", "top inner 40-pixel gradient from green to red; checks long narrow rows")) goto done;

  draw_checkerboard(cfg.width, cfg.height, true);
  if (step_wait("04-checker", "32-pixel blue/dark checkerboard below the gradient; checks many line draws")) goto done;

  draw_cross(cfg.width, cfg.height, true);
  if (step_wait("05-cross", "7-pixel red center cross overlays earlier content; checks overwrite order")) goto done;

  draw_corner_blocks(cfg.width, cfg.height, true);
  if (step_wait("06-final", "four corner blocks: red, green, blue, yellow; checks medium rectangles and final sync")) goto done;

done:
  printf("[gpu][DONE]\n");
  return 0;
}
