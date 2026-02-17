#include <stdio.h>

int main(void)
{
	int x = 123;
    int y = 4;
    int z = 5;

    // 1
    if (x > 0 && x < 10);
    else
        printf("x is out of range.\n");

    if (x <= 0 || x >= 10)
	    printf("x is out of range.\n");

    // 2
    if (x > 0)
        printf("Test OK!\n");
    else if (x <= 0 && y > 0)
        printf("Test OK!\n");
    else
        printf("Test failed!\n");

    if (x <= 0 && y <= 0)
        printf("Test failed!\n");
    else
        printf("Test OK!\n");

    // 3
    if (x > 1 && y != 1) {
    //    ...
    } else if (x < 1 && y != 1) {
    //    ...
    } else {    // x == 1 || y == 1
    //    ...
    }

    // 4
    if (x<3 && y>3)
        printf("Test OK!\n");
    /*else if (x>=3 && y>=3)
        printf("Test OK!\n");*/ // no need
    else if (z>3 && x>=3)
        printf("Test OK!\n");
    else if (z<=3 && y>=3)
        printf("Test OK!\n");
    else
        printf("Test failed!\n");

    return 0;
}