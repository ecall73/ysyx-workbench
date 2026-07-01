#include <am.h>
#include <klib.h>

void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  assert(kbd != NULL);
  kbd->keydown = 0;
  kbd->keycode = AM_KEY_NONE;
}
