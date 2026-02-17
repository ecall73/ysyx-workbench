#include <stdio.h>
#include <stdlib.h>
#define N 100
#define LOWER_BOUND 10
#define UPPER_BOUND 20

int a[N];

void gen_random(int lower_bound, int upper_bound)
{
	int i;
	for (i = 0; i < N; i++)
		a[i] = rand() % (upper_bound - lower_bound + 1) + lower_bound;
}

int howmany(int value)
{
	int count = 0, i;
	for (i = 0; i < N; i++)
		if (a[i] == value)
			++count;
	return count;
}

int main(void)
{
	int i, j;
	int counts[UPPER_BOUND - LOWER_BOUND + 1];
	int max_count = 0;
	
	gen_random(LOWER_BOUND, UPPER_BOUND);
	
	printf("value\thow many\n");
	for (i = LOWER_BOUND; i <= UPPER_BOUND; i++)
    {
		counts[i-LOWER_BOUND] = howmany(i);
		printf("%d\t%d\n", i, counts[i-LOWER_BOUND]);
		if (counts[i-LOWER_BOUND] > max_count)
			max_count = counts[i-LOWER_BOUND];
	}
	printf("\n\n");
	
	for (i = LOWER_BOUND; i <= UPPER_BOUND; i++)
		printf("%d\t", i);
	printf("\n\n");
	
	for (i = 1; i <= max_count; ++i)
    {
		for (j = 0; j < UPPER_BOUND - LOWER_BOUND + 1; j++)
        {
			if (counts[j] >= i)
				printf("*\t");
			else
				printf("\t");
		}
		printf("\n");
	}
	
	return 0;
}