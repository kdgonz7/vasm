## VASM Makefile
## Copyright (C) VOLT Foundation 2024-present

ASCIIDOCTOR=$(shell which asciidoctor)
FORMAT=manpage
WEB_FORMAT=html
all: tests app vasm.adoc stylist.adoc

clean:
	rm zig-out -rf
	rm .zig-cache -rf

tests:
	zig build tests

tests-summary:
	zig build tests --summary all

app:
	zig build --summary all

vasm.adoc:
	mkdir -p man/man1
	$(ASCIIDOCTOR) -b $(FORMAT) documentation/vasm.adoc -o man/man1/vasm.1

stylist.adoc:
	mkdir -p man/man1
	$(ASCIIDOCTOR) -b $(FORMAT) documentation/stylist.adoc -o man/man1/vasm-stylist.1

vasm-research:
	mkdir -p docs/
	$(ASCIIDOCTOR) -b $(WEB_FORMAT) docs/*.adoc

doc: vasm.adoc stylist.adoc

install: vasm.adoc install-man
	zig build --prefix /usr/local

install-man:
	cp man/man1/* /usr/local/man/man1

uninstall:
	rm /usr/local/bin/vasm
	rm /usr/local/man/man1/vasm.1

help:
	man man/man1/vasm.1
