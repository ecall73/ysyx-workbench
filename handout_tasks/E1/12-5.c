#include <stdio.h>
#include <stdbool.h>

#define MAX_ROW 5
#define MAX_COL 5

struct point { 
    int row, col; 
} queue[512];
int head = 0, tail = 0;
int queue_size = 16;

// 入队
bool enqueue(struct point p)
{
    if ((tail + 1) % queue_size == head)
        return false;  // 队列满

    queue[tail] = p;
    tail = (tail + 1) % queue_size;
    return true;
}

// 出队
bool dequeue(struct point *p)
{
    if (head == tail)
        return false;  // 队列空
    *p = queue[head];
    head = (head + 1) % queue_size;
    return true;
}

bool is_empty(void)
{
    return head == tail;
}

int maze[MAX_ROW][MAX_COL] =
{
    0, 1, 0, 0, 0,
    0, 1, 0, 1, 0,
    0, 0, 0, 0, 0,
    0, 1, 1, 1, 0,
    0, 0, 0, 1, 0,
};

void print_maze(void)
{
    int i, j;
    for (i = 0; i < MAX_ROW; i++)
    {
        for (j = 0; j < MAX_COL; j++)
            printf("%d ", maze[i][j]);
        putchar('\n');
    }
    printf("*********\n");
}

void visit(int row, int col)
{
    struct point visit_point = { row, col };
    maze[row][col] = 2;
    if (!enqueue(visit_point))
        printf("Quene is full!\n");
}

int main(void)
{
    struct point p = { 0, 0 };
    bool path_found = false;
    
    maze[p.row][p.col] = 2;
    enqueue(p);
    
    while (!is_empty()) {
        
        dequeue(&p);
        
        if (p.row == MAX_ROW - 1 && p.col == MAX_COL - 1)
        {
            path_found = true;
            break;
        }
        
        if (p.col+1 < MAX_COL && maze[p.row][p.col+1] == 0)
            visit(p.row, p.col+1);
        if (p.row+1 < MAX_ROW && maze[p.row+1][p.col] == 0)
            visit(p.row+1, p.col);
        if (p.col-1 >= 0 && maze[p.row][p.col-1] == 0)
            visit(p.row, p.col-1);
        if (p.row-1 >= 0 && maze[p.row-1][p.col] == 0)
            visit(p.row-1, p.col);
        
        // print_maze();
    }
    
    if (path_found)
        printf("有路能到达终点\n");
    else
        printf("没有路能到达终点\n");

    return 0;
}