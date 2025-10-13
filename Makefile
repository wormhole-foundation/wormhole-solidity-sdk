.DEFAULT_GOAL = build
.PHONY: build test clean

build:
	@$(MAKE) -C gen build
	forge build

test: build
	forge test

clean:
	@$(MAKE) -C gen clean
	forge clean
