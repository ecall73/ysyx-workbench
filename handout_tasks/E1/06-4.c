#include <stdio.h>
#include <math.h>

int is_prime(int n)
{
    int i;
    int isPrime = 1;
    
    if (n <= 1)
        return 0;
        
    for (i = 2; i < sqrt(n); i++)
    {
        if (n % i == 0)
        {
            isPrime = 0;
        }
    }
    
    return isPrime;
}

int main(void)
{
    int i;
    for (i = 1; i <= 100; i++)
    {
        if (is_prime(i))
        {
            printf("%d\n", i);
        }
    }
    return 0;
}
