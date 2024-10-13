## VASM Makefile
## Copyright (C) VOLT Foundation 2024-present

ASCIIDOCTOR=$(shell which asciidoctor)
FORMAT=manpage
all: tests app

clean:
	rm zig-out -rf
	rm .zig-cache -rf

tests:
	zig build tests

app:
	zig build

vasm.asciidoc:
	$(ASCIIDOCTOR) -b $(FORMAT) documentation/vasm.asciidoc -o man/vasm.1

doc: vasm.asciidoc
