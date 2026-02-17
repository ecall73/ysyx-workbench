#include <stdio.h>

void diamond(int n, char c)
{
    
    if (n % 2 == 0)
    {
        printf("2|n!\n");
        return;
    }
    
    for (int i = 0; i <= n / 2; i++)
    {
        for (int j = 0; j < n / 2 - i; j++)
            printf("\t");
        for (int k = 0; k < 2 * i + 1; k++)
        {
            printf("%c", c);
            if (k < 2 * i)
                printf("\t");
        }
        printf("\n");
    }
    
    for (int i = n / 2 - 1; i >= 0; i--)
    {
        for (int j = 0; j < n / 2 - i; j++)
            printf("\t");
        for (int k = 0; k < 2 * i + 1; k++)
        {
            printf("%c", c);
            if (k < 2 * i)
                printf("\t");
        }
        printf("\n");
    }
}

int main(void)
{
    diamond(3, '*');    
    diamond(5, '+');
    diamond(4, '#');
    
    return 0;
}