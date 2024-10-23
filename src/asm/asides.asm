[compat openlud]

; asides are essentially similar to macros except they define data to
; be expanded by the code generator.

:set MY_IMPORTANT_NUMBER 100
:set MY_IMPORTANT_CHAR1 'a'

_start:
; when the arguments are being expanded, the code generator will
; use any variables stored in the asides.
    echo MY_IMPORTANT_CHAR1
