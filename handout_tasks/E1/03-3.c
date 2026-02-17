#include <stdio.h>

void increment(int *x)
{
    // 改成传递指针就可以奏效
    // C++也可以使用引用
	*x = *x + 1;
}

int main(void)
{
	int i = 1, j = 2;
	increment(&i); /* i now becomes 2 */
	increment(&j); /* j now becomes 3 */

    printf("%d, %d",i,j);

	return 0;
}