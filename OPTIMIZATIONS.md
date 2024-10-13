# The VASM Optimizing Compiler

The VASM compiler is an optimizing compiler, meaning that it analyzes input source code and makes decisions that can benefit the code's performance and storage usage.

An optimization that comes with VASM is called **procedure folding**. Procedure Folding is the process of taking each method, generating its respective bytecode and, instead of constantly generating definitions, storing definitions and binary internally until it is used again. Procedure Folding is similar to macro expansion, in the sense that two functions which call the same procedure are the same size.

```asm
;; procedure 'a' calls `OR`, which in this fake environment is
;; worth a single byte. Procedure 'b' then calls procedure 'a', which
;; expands 'a' onto 'b' leading them to be the same size. On multiple
;; environments of different sizes, this code should yield similar sizes.

a:
    or
b:
    a   ;; b expands a
```

## Scope-aware Optimizations

### Dead Code

VASM has dead code elimination to get rid of unused procedures. Especially useful for non-folding programs for
platforms such as NexFUSE.

```asm
;; size: 5 bytes with definition
a:
    echo 'A';

;; size: 5 bytes with definition
b:
    echo 'A';

_start:
    a; ;; calls a, 5 byte expansion
```

Without dead code elimination the program size would be in total **`15` bytes**.

However, using dead code elimination, it reads through all of the used instructions and removes any that are unused.
DCE can bring the program down in size from 15 bytes to 10 bytes, enabling folding can drop the size down to 5 bytes, a 33% improvement.

### Empty Procedures

Empty procedures are discouraged in the LR Assembly standard and are error prone in VASM. Empty subroutines are not allowed.
