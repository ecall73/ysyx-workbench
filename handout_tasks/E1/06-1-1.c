#include <stdio.h>

int gcd(int a, int b)
{
    while(a % b)
    {
        int t = a;
        a = b;
        b = t % a;
    }

    return b;
}

int fib(int n)
{
    if(n <= 1)
        return 1;
    
    int prev1 = 1;
    int prev2 = 1;
    int current = 1;
    
    for(int i = 2; i <= n; ++i)
    {
        current = prev1 + prev2;
        prev2 = prev1;
        prev1 = current;
    }
    
    return current;
}

int main(void)
{
	int a = 512, b = 384;
    int n = 5;

    printf("%d, %d", gcd(a, b), fib(n));

    return 0;
}