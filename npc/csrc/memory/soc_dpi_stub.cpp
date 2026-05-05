#include <assert.h>
#include <stdint.h>

extern "C" void flash_read(int32_t addr, int32_t *data) {
    (void)addr;
    (void)data;
    assert(0);
}

extern "C" void mrom_read(int32_t addr, int32_t *data) {
    (void)addr;
    assert(data != nullptr);
    *data = 0x00100073;
}
