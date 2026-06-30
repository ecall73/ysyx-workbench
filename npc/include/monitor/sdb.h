#ifndef __NPC_MONITOR_SDB_H__
#define __NPC_MONITOR_SDB_H__

#include "common.h"

extern bool sdb_batch_mode;
extern bool sdb_quit;

uint32_t expr(char *e, bool *success);

int new_wp(char *e);
bool free_wp(int NO);
void wp_display();
bool wp_check();

void init_sdb();
void sdb_set_batch_mode();
void sdb_mainloop();

#endif
