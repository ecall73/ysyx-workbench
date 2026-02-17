    .text
    .globl main
main:
    li  t0, 10      # t0 = 10  (循环上限)
    li  t1, 0       # t1 = 0   (循环变量 i)
    li  t2, 0       # t2 = 0   (累加和 sum)
    li  t3, 1       # t3 = 1   (常数 1)

loop:
    add   t1, t1, t3      # t1 = t1 + 1   (i++)
    add   t2, t2, t1      # t2 = t2 + t1  (sum += i)
    bne   t0, t1, loop    # if (t0 != t1) goto loop

end:
    bne   t0, t3, end     # if (t0 != t3) goto end (无限循环)