#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>
#include <regex.h>

typedef uint32_t word_t;

// Mock logging
#define Log(format, ...) 
#define panic(format, ...) exit(1)

// Mock common macros
#define ARRLEN(arr) (int)(sizeof(arr) / sizeof(arr[0]))

// Include necessary headers but mock isa.h to avoid complex dependencies
#include <regex.h>
#define __ISA_H__
// Manually define what we need from isa.h or other headers
// We only need basic types which are already defined in common.h or by us
// expr.c includes isa.h, so we need to prevent it from failing

// Directly include expr.c to access static functions
// This avoids complex linking and dependency issues
// But we need to define some things first
#include "../../src/monitor/sdb/expr.c"

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <input_file>\n", argv[0]);
        return 1;
    }

    FILE *fp = fopen(argv[1], "r");
    if (!fp) {
        perror("Failed to open input file");
        return 1;
    }

    init_regex();

    char line[65536];
    int passed = 0;
    int failed = 0;

    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        
        uint32_t expected;
        char expr_buf[65536];
        
        if (sscanf(line, "%u %[^\n]", &expected, expr_buf) == 2) {
            bool success;
            word_t result = expr(expr_buf, &success);
            
            if (success && result == expected) {
                passed++;
            } else {
                failed++;
                printf("FAIL: %s\nExpected: %u, Got: %u (success=%d)\n", expr_buf, expected, result, success);
            }
        }
    }

    printf("Passed: %d, Failed: %d\n", passed, failed);
    fclose(fp);
    return failed == 0 ? 0 : 1;
}
