#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) 
{
    void *ptr;
    long long count = 0;
    size_t size = 1024 * 1024;
    
    while (1)
    {
        ptr = malloc(size);
        count++;
        
        if (ptr == NULL)
        {
            printf("总共分配了约 %lld MB 内存\n", count);
            break;
        }
        
        memset(ptr, 0, size);
        
        if (count % 100 == 0)
            printf("已分配 %lld MB...\n", count * size / (1024 * 1024));
    }
    
    return 0;
}