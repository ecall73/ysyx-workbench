#include "npc.h"
#include "verilated.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    init_monitor(argc, argv);
    engine_start();
    npc_cleanup();
    return is_exit_status_bad();
}
