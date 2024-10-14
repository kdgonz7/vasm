## VASM Makefile
## Copyright (C) VOLT Foundation 2024-present

ASCIIDOCTOR=$(shell which asciidoctor)
FORMAT=manpage
all: tests app vasm.adoc

clean:
	rm zig-out -rf
	rm .zig-cache -rf

tests:
	zig build tests --summary all

app:
	zig build

vasm.adoc:
	mkdir -p man/man1
	$(ASCIIDOCTOR) -b $(FORMAT) documentation/vasm.adoc -o man/man1/vasm.1

doc: vasm.adoc

install: vasm.adoc
	zig build --prefix /usr/local
	cp man/man1/* /usr/local/man/man1

uninstall:
	rm /usr/local/bin/vasm
	rm /usr/local/man/man1/vasm.1

help:
	man man/man1/vasm.1
