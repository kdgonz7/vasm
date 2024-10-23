; Algo.asm rewritten using VASM features
; a simple program that adds up a number 
; until it reaches a specified destination
[compat nexfuse]
[endian little]

; set our variables
:set destRegister R1
:set expectedRegister R2
:set outputRegister R3

; a - increments the dest register
a:
    each destRegister
    inc destRegister
    jmp c

; b - prints done
b:
    lsl outputRegister, 'D', 'O', 'N', 'E', 0x0a
    each outputRegister

; c - compares both registers and jumps to the done label if theyre done, otherwise increments both
c:
    cmp destRegister, expectedRegister, b, a

_start:
    mov expectedRegister, 254
    jmp c
