#include <stdio.h>

#define MAX_ROW 5
#define MAX_COL 5

struct point { int row, col; } stack[512];
int top = 0;

void push(struct point p)
{
	stack[top++] = p;
}

struct point pop(void)
{
	return stack[--top];
}

int is_empty(void)
{
	return top == 0;
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

/* 每个字节存储方向（1:左,2:上,3:右,4:下），0表示无前驱 */
unsigned char dir[MAX_ROW][MAX_COL] = {0};

/* visit不再使用堆栈，只标记迷宫并记录前驱方向 */
void visit(int row, int col, struct point pre)
{
	struct point visit_point = { row, col };
	maze[row][col] = 2;
	if (pre.row != -1)
    {
		if (pre.row == row && pre.col == col-1)
            dir[row][col] = 1;
		else if (pre.row == row-1 && pre.col == col)
            dir[row][col] = 2;
		else if (pre.row == row && pre.col == col+1)
            dir[row][col] = 3;
		else if (pre.row == row+1 && pre.col == col)
            dir[row][col] = 4;
	}
}

int dfs(struct point p)
{
	if (p.row == MAX_ROW-1 && p.col == MAX_COL-1)
		return 1;

	struct point neighbors[4];
	int count = 0;

	if (p.col+1 < MAX_COL && maze[p.row][p.col+1] == 0)
    {
		visit(p.row, p.col+1, p);
		neighbors[count++] = (struct point){p.row, p.col+1};
	}
	if (p.row+1 < MAX_ROW && maze[p.row+1][p.col] == 0)
    {
		visit(p.row+1, p.col, p);
		neighbors[count++] = (struct point){p.row+1, p.col};
	}
	if (p.col-1 >= 0 && maze[p.row][p.col-1] == 0)
    {
		visit(p.row, p.col-1, p);
		neighbors[count++] = (struct point){p.row, p.col-1};
	}
	if (p.row-1 >= 0 && maze[p.row-1][p.col] == 0)
    {
		visit(p.row-1, p.col, p);
		neighbors[count++] = (struct point){p.row-1, p.col};
	}

	print_maze();

	for (int i = count-1; i >= 0; i--)
		if (dfs(neighbors[i]))
			return 1;
	return 0;
}

int main(void)
{
	struct point p = { 0, 0 };

	maze[0][0] = 2;

	if (dfs(p))
    {
		struct point cur = { MAX_ROW-1, MAX_COL-1 };
		top = 0;
		while (1) {
			push(cur);
			if (cur.row == 0 && cur.col == 0) break;
			switch (dir[cur.row][cur.col]) {
				case 1: cur.col--; break;  // 来自左边
				case 2: cur.row--; break;  // 来自上边
				case 3: cur.col++; break;  // 来自右边
				case 4: cur.row++; break;  // 来自下边
			}
		}

		while (!is_empty()) {
			cur = pop();
			printf("(%d, %d)\n", cur.row, cur.col);
		}
	} else {
		printf("No path!\n");
	}

	return 0;
}