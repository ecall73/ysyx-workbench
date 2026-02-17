#include <stdio.h>
#define N 4
#define M 2
int a[N] = {1, 2, 3, 4};
int b[N];
int result[M];
int combination[M];

void swap(int *x, int *y)
{
    int temp = *x;
    *x = *y;
    *y = temp;
}

void copy_array()
{
    for (int i = 0; i < N; i++)
        b[i] = a[i];
}

void print_permutation_all(int *arr, int start, int end)
{
    if (start == end)
    {
        for (int i = 0; i <= end; i++)
            printf("%d\t", arr[i]);
        printf("\n");
        return;
    }
    
    for (int i = start; i <= end; i++)
    {
        swap(&arr[start], &arr[i]);
        print_permutation_all(arr, start + 1, end);
        swap(&arr[start], &arr[i]);
    }
}

void print_permutation_m(int *arr, int start, int end, int depth)
{
    if (depth == M)
    {
        for (int i = 0; i < M; i++)
            printf("%d\t", result[i]);
        printf("\n");
        return;
    }
    
    for (int i = start; i <= end; i++)
    {
        swap(&arr[start], &arr[i]);
        result[depth] = arr[start];
        print_permutation_m(arr, start + 1, end, depth + 1);
        swap(&arr[start], &arr[i]);
    }
}

void print_combination(int start, int depth)
{
    if (depth == M)
    {
        for (int i = 0; i < M; i++)
            printf("%d\t", combination[i]);
        printf("\n");
        return;
    }
    
    for (int i = start; i < N; i++)
    {
        combination[depth] = a[i];
        print_combination(i + 1, depth + 1);
    }
}

int main()
{
    printf("全排列 (%d个数):\n", N);
    copy_array();
    print_permutation_all(b, 0, N - 1);
    
    printf("\n从%d个数中取%d个数的排列:\n", N, M);
    copy_array();
    print_permutation_m(b, 0, N - 1, 0);
    
    printf("\n从%d个数中取%d个数的组合:\n", N, M);
    print_combination(0, 0);
    
    return 0;
}