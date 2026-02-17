#include <stdio.h>

int main(void)
{
	int n = 100;
    int counter = 0;

    int i = 1;
    while(i <= 100)
    {
        if(i % 10 == 9)
            ++counter;
        if(i / 10 % 10 == 9)
            ++counter;
        ++i;
    }

    printf("%d", counter);

    return 0;
}