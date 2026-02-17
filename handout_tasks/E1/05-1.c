#include <stdio.h>
#include <math.h>

int is_leap_year(int year)
{
    return (year % 400 == 0) || ((year % 100) && (year % 4 == 0));
}

double myround(double x)
{
    if (x >= 0)
        return floor(x + 0.5);   // 正数：加0.5后向下取整
    else
        return ceil(x - 0.5);    // 负数：减0.5后向上取整
}

int main(void)
{
	int year = 2100;
    double x = -3.51;

    printf("%d, %f", is_leap_year(year), myround(x));

    return 0;
}