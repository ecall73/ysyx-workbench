    .text
    .globl main
main:
    li  t0, 10
    li  t1, 0
    li  t2, 0
    li  t3, 1

loop:
    add   t1, t1, t3
    add   t2, t2, t1
    bne   t0, t1, loop

end:
    bne   t0, t3, end