build:
	zig build

test:
	zig build test

fmt:
	zig fmt src/*.zig

demo:
	zig build run -- src/testdata/beep.m4a
