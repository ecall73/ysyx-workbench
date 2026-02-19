#include <stdio.h>
#include <assert.h>
#include <math.h>

#define LEN 8
int a[LEN] = { 1, 2, 2, 2, 5, 6, 8, 9 };

int is_sorted(void)
{
	int i;
	for (i = 1; i < LEN; i++)
		if (a[i-1] > a[i])
			return 0;
	return 1;
}

int mustbe(int start, int end, int number)
{
	int i;
	for (i = 0; i < start; i++)
		if (a[i] == number)
			return 0;
	for (i = end+1; i < LEN; i++)
		if (a[i] == number)
			return 0;
	return 1;
}

int contains(int n)
{
	int i;
	for (i = 0; i < LEN; i++)
		if (a[i] == n)
			return 1;
	return 0;
}

int binarysearch(int number)
{
	int mid, start = 0, end = LEN - 1;

	assert(is_sorted()); /* Precondition */
	while (start <= end) {
		assert(mustbe(start, end, number)); /* Maintenance */
		mid = (start + end) / 2;
		if (a[mid] < number)
			start = mid + 1;
		else if (a[mid] > number)
			end = mid - 1;
		else {
            while (mid > start && a[mid-1] == number)
				mid--;
			assert(mid >= start && mid <= end
			       && a[mid] == number); /* Postcondition 1 */
			return mid;
		}
	}
	assert(!contains(number)); /* Postcondition 2 */
	return -1;
}


double mysqrt(double y)
{
    if (y < 0) return -1;
    if (y == 0 || y == 1) return y;
    
    double start = 0;
    double end = (y > 1) ? y : 1;
    double mid;
    
    while (1)
    {
        mid = (start + end) / 2;
        double square = mid * mid;
        
        if (fabs(square - y) < 1e-6)
            return mid;

        if (square < y)
            start = mid;
        else
            end = mid;
    }
}

double mypow_recursive(double x, int n)
{
    if (n == 0) return 1;
    if (n == 1) return x;
    
    double half = mypow_recursive(x, n / 2);
    
    if (n % 2 == 0)
        return half * half;
    else
        return half * half * x;
}

double mypow_loop(double x, int n)
{
    double result = 1;
    double base = x;
    int exponent = n;
    
    while (exponent > 0) {
        if (exponent % 2 == 1)
            result *= base;
        base *= base;
        exponent /= 2;
    }
    
    return result;
}

int main(void)
{
    printf("%d\n", binarysearch(2));
    
    printf("%f\n", mysqrt(1.25));
    
    printf("%f\n", mypow_recursive(2.56, 8));
    printf("%f\n", mypow_loop(2.56, 8));
    
    return 0;
}