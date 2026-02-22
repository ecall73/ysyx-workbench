#include <stdio.h>
#include <stdlib.h>

#define N 7
#define M 3

struct node
{
    int num;
    struct node *next;
};

int main(void)
{
    struct node *head = NULL;
    struct node *prev = NULL;
    for (int i = 1; i <= N; i++)
    {
        struct node *new_node = (struct node *)malloc(sizeof(struct node));
        new_node->num = i;
        new_node->next = NULL;
        if (head == NULL)
            head = new_node;
        else
            prev->next = new_node;
        prev = new_node;
    }

    if (prev != NULL)
        prev->next = head;

    struct node *current = head;
    struct node *prev_node = prev;

    for (int remaining = N; remaining > 1; --remaining)
    {
        // move
        for (int i = 1; i < M; i++)
        {
            prev_node = current;
            current = current->next;
        }

        // kill
        struct node *to_kill = current;
        printf("Kill %d\n", to_kill->num);
        prev_node->next = to_kill->next;
        current = to_kill->next;
        free(to_kill);

    }

    printf("Survivor: %d\n", current->num);
    free(current);

    return 0;
}