#include <stdio.h>

int main(int argc, char *argv[])
{
    int i = 0;

    argv[2] = "pp";

    // go through each string in argv
    // why am I skipping argv[0]?
    for(i = 1; i < argc; i++) {
        printf("arg %d: %s\n", i, argv[i]);
        if(i >= 2)
            break;
    }

    // let's make our own array of strings
    char *states[] = {
        argv[1], "Oregon",
        NULL, "Texas"
    };
    int num_states = 4;

    for(i = 0; i < num_states; i++) {
        printf("state %d: %s\n", i, states[i]);
        if(i >= 2)
            break;
    }

    return 0;
}