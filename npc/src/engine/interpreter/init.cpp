#include "monitor/monitor.h"
#include "monitor/sdb.h"

void engine_start() {
    sdb_mainloop();
}
