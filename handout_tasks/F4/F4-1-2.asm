    .text
    .globl main
main:
    li  t0, 9
    li  t1, -1
    li  t2, 0
    li  t3, 2

loop:
    add   t1, t1, t3
    add   t2, t2, t1
    bne   t0, t1, loop

end:
    bne   t0, t3, end