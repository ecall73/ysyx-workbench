#include <stdio.h>

int gcd(int a, int b)
{
    if(a % b == 0)
        return b;
    else
        return gcd(b, a % b);
}

int fib(int n)
{
    if(n <= 1)
        return 1;
    else
        return fib(n-1) + fib(n-2);
}

int main(void)
{
	int a = 512, b = 384;
    int n = 5;

    printf("%d, %d", gcd(a, b), fib(n));

    return 0;
}