#include <assert.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

#define SDL_malloc  malloc
#define SDL_free    free
#define SDL_realloc realloc

#define SDL_STBIMAGE_IMPLEMENTATION
#include "SDL_stbimage.h"

SDL_Surface* IMG_Load_RW(SDL_RWops *src, int freesrc) {
  assert(src->type == RW_TYPE_MEM);
  assert(freesrc == 0);
  return NULL;
}

SDL_Surface* IMG_Load(const char *filename) {
  int fd = open(filename, O_RDONLY);
  assert(fd >= 0);

  size_t size = lseek(fd, 0, SEEK_END);
  assert(lseek(fd, 0, SEEK_SET) == 0);
  void *buf = malloc(size);
  assert(buf);
  assert(read(fd, buf, size) == size);

  SDL_Surface *surface = STBIMG_LoadFromMemory(buf, size);
  close(fd);
  free(buf);
  return surface;
}

int IMG_isPNG(SDL_RWops *src) {
  return 0;
}

SDL_Surface* IMG_LoadJPG_RW(SDL_RWops *src) {
  return IMG_Load_RW(src, 0);
}

char *IMG_GetError() {
  return "Navy does not support IMG_GetError()";
}
