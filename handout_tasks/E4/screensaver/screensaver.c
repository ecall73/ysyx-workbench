#include <am.h>
#include <klib-macros.h>

#define STEPS 100
#define FPS_NORMAL 60
#define FPS_FAST 300

uint32_t colors[] = {
  0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffff00, 0xff00ff, 0x00ffff, 0xffffff
};

static inline uint8_t R(uint32_t c) { return (c >> 16) & 0xff; }
static inline uint8_t G(uint32_t c) { return (c >> 8) & 0xff; }
static inline uint8_t B(uint32_t c) { return c & 0xff; }
static inline uint32_t RGB(uint8_t r, uint8_t g, uint8_t b) {
  return (r << 16) | (g << 8) | b;
}

static int key_pressed_count = 0;
static bool key_state[256];

int update_keys() {
  AM_INPUT_KEYBRD_T ev = io_read(AM_INPUT_KEYBRD);
  while (ev.keycode != AM_KEY_NONE) {
    if (ev.keycode == AM_KEY_ESCAPE && ev.keydown) {
      halt(0);
    }
    
    if (ev.keycode < 256) {
      if (ev.keydown) {
        if (!key_state[ev.keycode]) {
          key_state[ev.keycode] = true;
          key_pressed_count++;
        }
      } else {
        if (key_state[ev.keycode]) {
          key_state[ev.keycode] = false;
          key_pressed_count--;
        }
      }
    }
    ev = io_read(AM_INPUT_KEYBRD);
  }
  return key_pressed_count > 0 ? FPS_FAST : FPS_NORMAL;
}

void draw(uint32_t color) {
  int w = io_read(AM_GPU_CONFIG).width;
  int h = io_read(AM_GPU_CONFIG).height;
  uint32_t pixels[w];
  for (int i = 0; i < w; i++) {
    pixels[i] = color;
  }
  for (int y = 0; y < h; y++) {
    io_write(AM_GPU_FBDRAW, 0, y, pixels, w, 1, false);
  }
  io_write(AM_GPU_FBDRAW, 0, 0, NULL, 0, 0, true);
}

int main() {
  ioe_init();
  uint32_t curr = colors[0];
  
  while (1) {
    int next_idx = io_read(AM_TIMER_UPTIME).us % (sizeof(colors) / sizeof(colors[0]));
    uint32_t target = colors[next_idx];
    
    int r1 = R(curr), g1 = G(curr), b1 = B(curr);
    int r2 = R(target), g2 = G(target), b2 = B(target);
    
    for (int k = 0; k <= STEPS; k++) {
      uint8_t r = r1 + (r2 - r1) * k / STEPS;
      uint8_t g = g1 + (g2 - g1) * k / STEPS;
      uint8_t b = b1 + (b2 - b1) * k / STEPS;
      draw(RGB(r, g, b));
      
      int current_fps = update_keys();
      uint64_t next_frame = io_read(AM_TIMER_UPTIME).us + 1000000 / current_fps;
      while (io_read(AM_TIMER_UPTIME).us < next_frame);
    }
    curr = target;
  }
  return 0;
}