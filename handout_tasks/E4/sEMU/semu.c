#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

uint8_t PC = 0;
uint8_t R[4];
uint8_t M[16];

void inst_cycle()
{
    // fetch
    uint8_t inst = M[PC];
    
    // decode
    uint8_t opcode = (inst >> 6) & 0x03;
    uint8_t rd = (inst >> 4) & 0x03;
    uint8_t rs1 = (inst >> 2) & 0x03;
    uint8_t rs2 = inst & 0x03;
    uint8_t imm = inst & 0x0f;
    uint8_t addr = (inst >> 2) & 0x0f;

    // execute & writeback
    switch(opcode)
    {
        case 0x00:  // add
            R[rd] = R[rs1] + R[rs2];
            PC += 1;
            break;
        case 0x01:  // out
            printf("%d\n", R[rs2]);
            PC += 1;
            break;
        case 0x02:  // li
            R[rd] = imm;
            PC += 1;
            break;
        case 0x03:  // bner0
            if(R[rs2] != R[0])
                PC = addr;
            else
                PC += 1;
            break;
        default:
            printf("ERROR: Unsupported instruction at PC=%d, inst=0x%02X\n", PC, inst);
            exit(1);
    }
}

int main(int argc, char *argv[])
{ 
    FILE *fp = fopen(argv[1], "r"); 
    size_t bytes_read = fread(M, 1, 16, fp);
    if (bytes_read != 16)
    {
        printf("Load %ld inst\n", bytes_read);
        // 处理错误情况
        if (ferror(fp))
        {
            printf("Error: File read error\n");
            exit(1);
        }
    }
    fclose(fp); 
    for (int i = 0; i < 100; i ++) { inst_cycle(); } 
    return 0; 
 }

/*
 7  6 5  4 3   2 1   0
+----+----+-----+-----+
| 00 | rd | rs1 | rs2 | R[rd]=R[rs1]+R[rs2]         add指令, 寄存器相加
+----+----+-----+-----+
| 01 |          | rs2 | print(R[rs2])               out指令, 打印寄存器值
+----+----+-----+-----+
| 10 | rd |    imm    | R[rd]=imm                   li指令, 装入立即数, 高位补0
+----+----+-----+-----+
| 11 |   addr   | rs2 | if (R[0]!=R[rs2]) PC=addr   bner0指令, 若不等于R[0]则跳转
+----+----------+-----+
*/