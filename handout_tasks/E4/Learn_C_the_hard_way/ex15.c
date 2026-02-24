#include <stdio.h>

int main(int argc, char *argv[])
{
    int ages[] = {23, 43, 12, 89, 2};
    char *names[] = {
        "Alan", "Frank",
        "Mary", "John", "Lisa"
    };

    int count = sizeof(ages) / sizeof(int);
    int i = 0;

    int *cur_age = ages;
    char **cur_name = names;

    i = 0;
    while(i < count) {
        printf("%s has %d years alive.\n",
                *(names + i), *(ages + i));
        i++;
    }

    printf("---\n");

    i = 0;
    while(i < count) {
        printf("%s is %d years old.\n",
                cur_name[i], cur_age[i]);
        i++;
    }

    printf("---\n");

    i = 0;
    while(i < count) {
        printf("%s is %d years old again.\n",
                *(names + i), *(ages + i));
        i++;
    }

    printf("---\n");

    cur_name = names;
    cur_age = ages;
    while((cur_age - ages) < count) {
        printf("%s lived %d years so far.\n",
                *(cur_name), *(cur_age));
        cur_name++;
        cur_age++;
    }

    printf("---\n");

    printf("Addresses of names and ages:\n");
    i = 0;
    while(i < count) {
        printf("names[%d] = %p, ages[%d] = %p\n",
                i, (void *)(names + i), i, (void *)(ages + i));
        i++;
    }

    printf("---\n");

    printf("Command line arguments:\n");
    i = 0;
    while(i < argc) {
        printf("argv[%d] = %s at address %p\n",
                i, *(argv + i), (void *)(argv + i));
        i++;
    }

    return 0;
}