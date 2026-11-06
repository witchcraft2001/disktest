.PHONY: build test
build:
	@mkdir -p build
	sjasmplus --lst=build/disktest.lst --sym=build/disktest.sym disktest.asm

test: build
	node tests/run.js
