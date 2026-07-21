#include <NDL.h>
#include <SDL.h>
#include <assert.h>
#include <string.h>

#define keyname(k) #k,

static const char *keyname[] = {
  "NONE",
  _KEYS(keyname)
};
static uint8_t key_state[sizeof(keyname) / sizeof(keyname[0])];

int SDL_PushEvent(SDL_Event *ev) {
  return 0;
}

int SDL_PollEvent(SDL_Event *ev) {
  assert(ev);
  char buf[64];
  if (!NDL_PollEvent(buf, sizeof(buf))) return 0;

  buf[strlen(buf) - 1] = '\0';
  ev->type = buf[1] == 'd' ? SDL_KEYDOWN : SDL_KEYUP;
  for (int i = 1; i < (int)(sizeof(keyname) / sizeof(keyname[0])); i++) {
    if (strcmp(buf + 3, keyname[i]) == 0) {
      ev->key.keysym.sym = i;
      key_state[i] = (ev->type == SDL_KEYDOWN);
      return 1;
    }
  }

  assert(0);
  return 0;
}

int SDL_WaitEvent(SDL_Event *event) {
  while (!SDL_PollEvent(event));
  return 1;
}

int SDL_PeepEvents(SDL_Event *ev, int numevents, int action, uint32_t mask) {
  return 0;
}

uint8_t* SDL_GetKeyState(int *numkeys) {
  if (numkeys != NULL) *numkeys = sizeof(key_state);
  return key_state;
}
