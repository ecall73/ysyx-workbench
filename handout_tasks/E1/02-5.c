#include <stdio.h>

int main()
{
    int x, n;
    int quotient, remainder;

    x = 17;
    n = 4;

    quotient = x / n;
    remainder = x % n;
    if(remainder)
        ++quotient;
    printf("%d", quotient);
    
    return 0;
}