all: tests app

clean:
	rm zig-out -rf
	rm .zig-cache -rf

tests:
	zig build tests

app:
	zig build
