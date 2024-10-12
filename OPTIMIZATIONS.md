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

VASM can error out on unused register writes and reads by judging the instructions passed into the procedures. While the feature is useful it can potentially lead to slower compile times and therefore is disabled by default. These tags will
also need to be provided by the virtual instruction set implementation using functions like `registerWrite()` and `registerRead()`.

### Empty Procedures

Empty procedures are discouraged in the LR Assembly standard and are error prone in VASM. Empty subroutines are not allowed.
