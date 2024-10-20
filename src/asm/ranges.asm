; Ranges are functionality that is not implemented for any bytecode VM but
; are specified in the standard.
;
; Ranges have the syntax {S:E} where S is the start of the range and E is the end.
; They can also be used just like normal parameters.

_start:
    ranges {1:5}
    ranges R1, {1:5}
