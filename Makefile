build:
	zig build

test:
	zig build test

fmt:
	zig fmt src/*.zig

demo:
	zig build run -- -i src/testdata/beep.m4a -o zig-out/chapters

clean:
	rm -rf .zig-cache zig-out
