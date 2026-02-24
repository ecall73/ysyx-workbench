#include <stdio.h>

int main(int argc, char *argv[])
{
    if(argc < 2) {
        printf("ERROR: You need one argument.\n");
        // this is how you abort a program
        return 1;
    }

    for(int j = 1; j < argc; ++j)
    {
        char letter = argv[j][0];

        printf("Analyzing argv[%d]\n", j);

        for(int i = 0; argv[j][i] != '\0'; letter = argv[j][++i]) {
            // char letter = argv[1][i];

            if(letter >= 'A' && letter <= 'Z')
                letter += 32;

        if(letter == 'a' || letter == 'e' || letter == 'i' || letter == 'o' || letter == 'u' || (letter == 'y' && i > 2)) {
            printf("%d: '%c'\n", i, letter);
        }
        else {
            printf("%d: %c is not a vowel\n", i, letter);
        }
        }
    }

    return 0;
}