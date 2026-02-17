#include <stdio.h>

void copy_array(int dest[], int src[], int size)
{
    for (int i = 0; i < size; ++i)
        dest[i] = src[i];
}

int main()
{
    int source[5] = {1, 2, 3, 4, 5};
    int destination[5];
    
    copy_array(destination, source, 5);
    
    for (int i = 0; i < 5; i++)
        printf("%d\t", destination[i]);
    printf("\n");
    
    return 0;
}