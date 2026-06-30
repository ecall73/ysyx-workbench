#include "monitor/monitor.h"

int main(int argc, char **argv) {
    init_monitor(argc, argv);
    engine_start();
    npc_cleanup();
    return is_exit_status_bad();
}
