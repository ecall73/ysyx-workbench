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
  if (fd < 0) return NULL;

  off_t size = lseek(fd, 0, SEEK_END);
  void *buf = NULL;
  SDL_Surface *surface = NULL;
  if (size > 0 && lseek(fd, 0, SEEK_SET) == 0) {
    buf = malloc(size);
    if (buf != NULL && read(fd, buf, size) == size) {
      surface = STBIMG_LoadFromMemory(buf, size);
    }
  }

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
