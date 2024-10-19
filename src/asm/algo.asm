; $Id: algo.asm

; simple algorithm
; [compat nexfuse]

a:
; increment R1, this will go up until it's equal to 'A'
  inc R1
; jump back to comparisons
; forward referencing
  jmp d

; it'll just print 'DONE'
b:
  lsl R3, 'D', 'O', 'N', 'E', 0x0a
  each R3

c:
; we're going to compare R1 and R2, if R1 is 'A', we'll jump to b, otherwise
; we'll go to `a' and see what we can do from there
  cmp R1, R2, b, a

d:
  jmp c

_start:
; dest reg
  mov R2, 65
; jmp to compare sub
  jmp c
