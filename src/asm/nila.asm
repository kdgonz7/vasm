[compat nexfuse]

; in LR asm, the 'nil' type essentially represents nothing.
; but unlike NULL types, this doesn't explicitly return ZERO, and can not
; be CAST to 0. NIL is its own type which can be read and wrote as NIL.

; try it! using the NexFUSE language runtime this
; code will fail under an "InstructionError"

_start:
; compiler can not compile this because echo expects a char
    echo nil
