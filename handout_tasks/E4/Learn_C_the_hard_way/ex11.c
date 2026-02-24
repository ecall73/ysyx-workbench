#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[])
{
    // go through each string in argv

    int i = argc - 1;
    while(i >= 0) {
        printf("arg %d: %s\n", i, argv[i]);
        --i;
        if(i < 2)
            break;
    }

    // let's make our own array of strings
    char *states[] = {
        "California", "Oregon",
        "Washington", "Texas"
    };

    for(int j = 0; j < 4; ++j)
        states[j] = argv[j+1];

    int num_states = 4;
    i = num_states - 1;  // watch for this
    while(i >= 0) {
        printf("state %d: %s\n", i, states[i]);
        --i;
        if(i < 2)
            break;
    }

    return 0;
}