/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "sdb.h"

#define NR_WP 32

typedef struct watchpoint {
  int NO;
  struct watchpoint *next;

  /* TODO: Add more members if necessary */
  char expr[128];      // The expression to watch
  word_t old_val;      // The previous value of the expression
  bool enabled;        // Whether the watchpoint is enabled (though NO is enough, this helps)
} WP;

static WP wp_pool[NR_WP] = {};
static WP *head = NULL, *free_ = NULL;

void init_wp_pool() {
  int i;
  for (i = 0; i < NR_WP; i ++) {
    wp_pool[i].NO = i;
    wp_pool[i].next = (i == NR_WP - 1 ? NULL : &wp_pool[i + 1]);
  }

  head = NULL;
  free_ = wp_pool;
}

/* TODO: Implement the functionality of watchpoint */

WP* new_wp() {
  if (free_ == NULL) {
    panic("No more watchpoints available");
  }

  WP *wp = free_;
  free_ = free_->next;

  wp->next = head;
  head = wp;

  wp->enabled = true;
  wp->expr[0] = '\0';
  wp->old_val = 0;

  return wp;
}

void free_wp(WP *wp) {
  if (wp == NULL) return;

  if (head == wp) {
    head = wp->next;
  } else {
    WP *prev = head;
    while (prev != NULL && prev->next != wp) {
      prev = prev->next;
    }
    if (prev != NULL) {
      prev->next = wp->next;
    }
  }

  wp->next = free_;
  free_ = wp;
  wp->enabled = false;
}

// Add a new watchpoint
int wp_new(char *e) {
  bool success;
  word_t val = expr(e, &success);
  if (!success) {
    return -1;
  }

  WP *wp = new_wp();
  strncpy(wp->expr, e, 127);
  wp->expr[127] = '\0';
  wp->old_val = val;
  return wp->NO;
}

// Delete a watchpoint by NO
bool wp_free(int no) {
  WP *wp = head;
  while (wp != NULL) {
    if (wp->NO == no) {
      free_wp(wp);
      return true;
    }
    wp = wp->next;
  }
  return false;
}

// List all watchpoints
void wp_display() {
  if (head == NULL) {
    printf("No watchpoints.\n");
    return;
  }
  
  printf("%-8s %-16s %s\n", "Num", "Value", "Expression");
  WP *wp = head;
  while (wp != NULL) {
    printf("%-8d %-16u %s\n", wp->NO, wp->old_val, wp->expr);
    wp = wp->next;
  }
}

// Check if any watchpoint triggers
bool wp_check() {
  bool trigger = false;
  WP *wp = head;
  while (wp != NULL) {
    bool success;
    word_t new_val = expr(wp->expr, &success);
    if (success) {
      if (new_val != wp->old_val) {
        printf("Watchpoint %d: %s\n", wp->NO, wp->expr);
        printf("Old value = %u\n", wp->old_val);
        printf("New value = %u\n", new_val);
        wp->old_val = new_val;
        trigger = true;
      }
    } else {
      // If evaluation fails (shouldn't happen if created successfully), warn user?
      // Or maybe expression became invalid?
    }
    wp = wp->next;
  }
  return trigger;
}

