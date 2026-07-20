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

enum {FD_STDIN, FD_STDOUT, FD_STDERR, FD_FB, FD_EVENTS, FD_DISPINFO};

size_t invalid_read(void *buf, size_t offset, size_t len) {
  panic("should not reach here");
  return 0;
}

size_t invalid_write(const void *buf, size_t offset, size_t len) {
  panic("should not reach here");
  return 0;
}

extern size_t serial_write(const void *buf, size_t offset, size_t len);
extern size_t events_read(void *buf, size_t offset, size_t len);
extern size_t dispinfo_read(void *buf, size_t offset, size_t len);
extern size_t fb_write(const void *buf, size_t offset, size_t len);

/* This is the information about all files in disk. */
static Finfo file_table[] __attribute__((used)) = {
  [FD_STDIN]  = {"stdin", 0, 0, 0, invalid_read, invalid_write},
  [FD_STDOUT] = {"stdout", 0, 0, 0, invalid_read, serial_write},
  [FD_STDERR] = {"stderr", 0, 0, 0, invalid_read, serial_write},
  [FD_FB]     = {"/dev/fb", 0, 0, 0, invalid_read, fb_write},
  [FD_EVENTS] = {"/dev/events", 0, 0, 0, events_read, invalid_write},
  [FD_DISPINFO] = {"/proc/dispinfo", 0, 0, 0, dispinfo_read, invalid_write},
#include "files.h"
};

extern size_t ramdisk_read(void *buf, size_t offset, size_t len);
extern size_t ramdisk_write(const void *buf, size_t offset, size_t len);

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

  return -1;
}

const char *fs_file_name(int fd) {
  return get_file(fd)->name;
}

size_t fs_read(int fd, void *buf, size_t len) {
  Finfo *file = get_file(fd);
  if (file->read != NULL) {
    len = file->read(buf, file->open_offset, len);
  } else {
    if (file->open_offset == file->size) {
      return 0;
    }
    if (len > file->size - file->open_offset) {
      len = file->size - file->open_offset;
    }
    len = ramdisk_read(buf, file->disk_offset + file->open_offset, len);
  }
  file->open_offset += len;
  return len;
}

size_t fs_write(int fd, const void *buf, size_t len) {
  Finfo *file = get_file(fd);
  if (file->write != NULL) {
    len = file->write(buf, file->open_offset, len);
  } else {
    if (file->open_offset == file->size) {
      return 0;
    }
    if (len > file->size - file->open_offset) {
      len = file->size - file->open_offset;
    }
    len = ramdisk_write(buf, file->disk_offset + file->open_offset, len);
  }
  file->open_offset += len;
  return len;
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
  return 0;
}

void init_fs() {
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  file_table[FD_FB].size = cfg.width * cfg.height * sizeof(uint32_t);
}
