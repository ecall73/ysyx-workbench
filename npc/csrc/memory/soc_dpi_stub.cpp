#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "npc.h"

static uint8_t flash_image[NPC_FLASH_SIZE];
static bool flash_initialized = false;
static bool flash_oob_warned = false;
static bool flash_boot_loaded = false;
static size_t flash_boot_size = 0;

void flash_init_default_image() {
    // NOR flash erased state is all 1s.
    memset(flash_image, 0xff, sizeof(flash_image));
    flash_initialized = true;
    flash_oob_warned = false;
    flash_boot_loaded = false;
    flash_boot_size = 0;
    printf("Flash image initialized: erased state(0xFF), size = %u\n", NPC_FLASH_SIZE);
}

bool flash_load_boot_image(const char *img_file) {
    if (img_file == NULL) {
        fprintf(stderr, "flash_load_boot_image: null image path\n");
        return false;
    }
    if (!flash_initialized) {
        flash_init_default_image();
    }

    FILE *fp = fopen(img_file, "rb");
    if (fp == NULL) {
        fprintf(stderr, "flash_load_boot_image: failed to open %s\n", img_file);
        return false;
    }

    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        fprintf(stderr, "flash_load_boot_image: failed to seek %s\n", img_file);
        return false;
    }
    long size = ftell(fp);
    if (size < 0) {
        fclose(fp);
        fprintf(stderr, "flash_load_boot_image: failed to tell size for %s\n", img_file);
        return false;
    }
    if ((uint32_t)size > NPC_FLASH_SIZE) {
        fclose(fp);
        fprintf(stderr, "flash_load_boot_image: image too large (%ld > %u): %s\n",
                size, NPC_FLASH_SIZE, img_file);
        return false;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        fprintf(stderr, "flash_load_boot_image: failed to rewind %s\n", img_file);
        return false;
    }

    // Erase full flash before programming a new boot image.
    memset(flash_image, 0xff, sizeof(flash_image));
    size_t nread = fread(flash_image, 1, (size_t)size, fp);
    fclose(fp);
    if (nread != (size_t)size) {
        fprintf(stderr, "flash_load_boot_image: read size mismatch for %s\n", img_file);
        return false;
    }

    flash_boot_loaded = true;
    flash_boot_size = (size_t)size;
    flash_oob_warned = false;
    printf("Flash boot image loaded: %s, size = %ld, base = 0x%08x\n",
           img_file, size, NPC_FLASH_BASE);
    return true;
}

bool flash_get_boot_image_info(uint32_t *base, const uint8_t **img, size_t *size) {
    if (!flash_boot_loaded) {
        return false;
    }
    if (base != NULL) {
        *base = NPC_FLASH_BASE;
    }
    if (img != NULL) {
        *img = flash_image;
    }
    if (size != NULL) {
        *size = flash_boot_size;
    }
    return true;
}

extern "C" void flash_read(int32_t addr, int32_t *data) {
    assert(data != nullptr);

    if (!flash_initialized) {
        flash_init_default_image();
    }

    uint32_t uaddr = (uint32_t)addr;
    if (uaddr > (NPC_FLASH_SIZE - 4u)) {
        if (!flash_oob_warned) {
            fprintf(stderr, "flash_read: address out of range: 0x%08x\n", uaddr);
            flash_oob_warned = true;
        }
        *data = -1;
        return;
    }

    uint32_t offset = uaddr & ~0x3u;
    *data = (int32_t)(
        ((uint32_t)flash_image[offset + 0]) |
        ((uint32_t)flash_image[offset + 1] << 8) |
        ((uint32_t)flash_image[offset + 2] << 16) |
        ((uint32_t)flash_image[offset + 3] << 24)
    );
}

extern "C" void mrom_read(int32_t addr, int32_t *data) {
    (void)addr;
    assert(data != nullptr);
    *data = 0x00000013;  // nop
}
