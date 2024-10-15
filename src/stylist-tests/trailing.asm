_start:
;;# initialize all used registers
    init R1;B2
    ;; note: this still compiles fine and the comma next input is just ignored
    init R2,
    echo 'A'
