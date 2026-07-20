#include <NDL.h>
#include <SDL.h>
#include <assert.h>
#include <string.h>

#define keyname(k) #k,

static const char *keyname[] = {
  "NONE",
  _KEYS(keyname)
};

int SDL_PushEvent(SDL_Event *ev) {
  return 0;
}

int SDL_PollEvent(SDL_Event *ev) {
  return 0;
}

int SDL_WaitEvent(SDL_Event *event) {
  char buf[64];
  while (!NDL_PollEvent(buf, sizeof(buf)));

  buf[strlen(buf) - 1] = '\0';
  event->type = buf[1] == 'd' ? SDL_KEYDOWN : SDL_KEYUP;
  for (int i = 1; i < (int)(sizeof(keyname) / sizeof(keyname[0])); i++) {
    if (strcmp(buf + 3, keyname[i]) == 0) {
      event->key.keysym.sym = i;
      return 1;
    }
  }

  assert(0);
  return 0;
}

int SDL_PeepEvents(SDL_Event *ev, int numevents, int action, uint32_t mask) {
  return 0;
}

uint8_t* SDL_GetKeyState(int *numkeys) {
  return NULL;
}
