#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const uint32_t kMromBase = 0x20000000u;
static const uint32_t kMromSize = 0x1000u;
static uint8_t mrom_image[kMromSize];
static size_t mrom_image_size = 0;
static bool mrom_loaded = false;
static bool mrom_oob_warned = false;

bool mrom_load_image(const char *img_file) {
    if (img_file == NULL) {
        fprintf(stderr, "mrom_load_image: null image path\n");
        return false;
    }

    FILE *fp = fopen(img_file, "rb");
    if (fp == NULL) {
        fprintf(stderr, "mrom_load_image: failed to open %s\n", img_file);
        return false;
    }

    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        fprintf(stderr, "mrom_load_image: failed to seek %s\n", img_file);
        return false;
    }
    long size = ftell(fp);
    if (size < 0) {
        fclose(fp);
        fprintf(stderr, "mrom_load_image: failed to tell size for %s\n", img_file);
        return false;
    }
    if ((uint32_t)size > kMromSize) {
        fclose(fp);
        fprintf(stderr, "mrom_load_image: image too large (%ld > %u): %s\n",
                size, kMromSize, img_file);
        return false;
    }

    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        fprintf(stderr, "mrom_load_image: failed to rewind %s\n", img_file);
        return false;
    }

    memset(mrom_image, 0, sizeof(mrom_image));
    size_t nread = fread(mrom_image, 1, (size_t)size, fp);
    fclose(fp);
    if (nread != (size_t)size) {
        fprintf(stderr, "mrom_load_image: read size mismatch for %s\n", img_file);
        return false;
    }

    mrom_loaded = true;
    mrom_image_size = (size_t)size;
    mrom_oob_warned = false;
    printf("MROM image loaded: %s, size = %ld\n", img_file, size);
    return true;
}

bool mrom_get_image_info(uint32_t *base, const uint8_t **img, size_t *size) {
    if (!mrom_loaded) {
        return false;
    }
    if (base != NULL) {
        *base = kMromBase;
    }
    if (img != NULL) {
        *img = mrom_image;
    }
    if (size != NULL) {
        *size = mrom_image_size;
    }
    return true;
}

extern "C" void flash_read(int32_t addr, int32_t *data) {
    (void)addr;
    (void)data;
    assert(0);
}

extern "C" void mrom_read(int32_t addr, int32_t *data) {
    assert(data != nullptr);

    if (!mrom_loaded) {
        *data = 0x00000013;  // nop
        return;
    }

    uint32_t uaddr = (uint32_t)addr;
    if (uaddr < kMromBase || uaddr > (kMromBase + kMromSize - 4)) {
        if (!mrom_oob_warned) {
            fprintf(stderr, "mrom_read: address out of range: 0x%08x\n", uaddr);
            mrom_oob_warned = true;
        }
        *data = 0x00000013;  // nop
        return;
    }

    uint32_t offset = (uaddr - kMromBase) & ~0x3u;
    *data = (int32_t)(
        ((uint32_t)mrom_image[offset + 0]) |
        ((uint32_t)mrom_image[offset + 1] << 8) |
        ((uint32_t)mrom_image[offset + 2] << 16) |
        ((uint32_t)mrom_image[offset + 3] << 24)
    );
}
