#include <stdio.h>

void print_x(int x)
{
	printf("%d, %d", x % 100 / 10, x % 10);
}

int main(void)
{
	int x = 123;
    print_x(x);

	return 0;
}