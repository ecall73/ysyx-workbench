#include <stdio.h>
#define N 10
#define K 2

void swap(int *a, int *b)
{
    int temp = *a;
    *a = *b;
    *b = temp;
}

int partition(int a[], int start, int end)
{
    int pivot = a[start];
    int i = start + 1;
    int j = end;
    
    while (i <= j)
    {
        while (i <= j && a[i] <= pivot)
            i++;
        while (i <= j && a[j] > pivot)
            j--;
        if (i < j)
            swap(&a[i], &a[j]);
    }
    swap(&a[start], &a[j]);
    return j;
}

void quicksort(int a[], int start, int end)
{
    int mid;
    if (end > start)
    {
        mid = partition(a, start, end);
        quicksort(a, start, mid - 1);
        quicksort(a, mid + 1, end);
    }
}

int quick_select(int a[], int start, int end, int k)
{
    if (start == end)
        return a[start];
    
    int mid = partition(a, start, end);
    
    if (k == mid)
        return a[mid];
    else if (k < mid)
        return quick_select(a, start, mid - 1, k);
    else
        return quick_select(a, mid + 1, end, k);
}

int main()
{
    int arr1[] = {64, 34, 25, 12, 22, 11, 90, 0, -5, -7};
    
    for (int i = 0; i < N; i++)
        printf("%d ", arr1[i]);
    printf("\n");
        
    int result = quick_select(arr1, 0, N - 1, K);
    printf("arr[%d]: %d\n", K, result);
    
    int sorted[N];
    for (int i = 0; i < N; i++)
        sorted[i] = arr1[i];
    
    quicksort(sorted, 0, N - 1);
    
    for (int i = 0; i < N; i++) printf("%d ", sorted[i]);
    printf("\n");
    
    return 0;
}
