#include <fs.h>

typedef size_t (*ReadFn) (void *buf, size_t offset, size_t len);
typedef size_t (*WriteFn) (const void *buf, size_t offset, size_t len);

typedef struct {
  char *name;
  size_t size;
  size_t disk_offset;
  size_t open_offset;
  ReadFn read;
  WriteFn write;
} Finfo;

enum {FD_STDIN, FD_STDOUT, FD_STDERR, FD_FB};

static size_t invalid_read(void *buf, size_t offset, size_t len) {
  panic("should not reach here");
  return 0;
}

static size_t invalid_write(const void *buf, size_t offset, size_t len) {
  panic("should not reach here");
  return 0;
}

/* This is the information about all files in disk. */
static Finfo file_table[] __attribute__((used)) = {
  [FD_STDIN]  = {"stdin", 0, 0, 0, invalid_read, invalid_write},
  [FD_STDOUT] = {"stdout", 0, 0, 0, invalid_read, invalid_write},
  [FD_STDERR] = {"stderr", 0, 0, 0, invalid_read, invalid_write},
#include "files.h"
};

extern size_t ramdisk_read(void *buf, size_t offset, size_t len);

#define NR_FILES (sizeof(file_table) / sizeof(file_table[0]))

static Finfo *get_file(int fd) {
  assert(fd >= 0 && fd < (int)NR_FILES);
  return &file_table[fd];
}

int fs_open(const char *pathname, int flags, int mode) {
  (void)flags;
  (void)mode;

  for (int i = 0; i < (int)NR_FILES; i ++) {
    if (strcmp(pathname, file_table[i].name) == 0) {
      file_table[i].open_offset = 0;
      return i;
    }
  }

  assert(0);
  return -1;
}

size_t fs_read(int fd, void *buf, size_t len) {
  Finfo *file = get_file(fd);
  if (fd <= FD_STDERR || file->open_offset == file->size) {
    return 0;
  }

  size_t nread = len;
  if (nread > file->size - file->open_offset) {
    nread = file->size - file->open_offset;
  }

  if (file->read != NULL) {
    nread = file->read(buf, file->open_offset, nread);
  } else {
    nread = ramdisk_read(buf, file->disk_offset + file->open_offset, nread);
  }
  file->open_offset += nread;
  return nread;
}

size_t fs_lseek(int fd, size_t offset, int whence) {
  Finfo *file = get_file(fd);
  size_t new_offset;

  switch (whence) {
    case SEEK_SET:
      new_offset = offset;
      break;
    case SEEK_CUR:
      assert(offset <= file->size - file->open_offset);
      new_offset = file->open_offset + offset;
      break;
    case SEEK_END:
      assert(offset == 0);
      new_offset = file->size;
      break;
    default:
      assert(0);
      return 0;
  }

  assert(new_offset <= file->size);
  file->open_offset = new_offset;
  return new_offset;
}

int fs_close(int fd) {
  get_file(fd);
  return 0;
}

void init_fs() {
  // TODO: initialize the size of /dev/fb
}
