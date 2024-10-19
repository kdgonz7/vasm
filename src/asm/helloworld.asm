; [compat nexfuse]

_start:
    zeroall ; clear all registers
    lsl R1,'h','e','l','l','o',' ','w','o','r','l','d',0x0a
    each R1 ; print out R1
