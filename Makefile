#the chain that will be forked for testing
TEST_FORK = Mainnet Ethereum

.DEFAULT_GOAL = build
.PHONY: build test clean

build:
	@$(MAKE) -C gen build
	forge build

#include (and build if necessary) env/testing.env if we're running tests
ifneq (,$(filter test, $(MAKECMDGOALS)))
#hacky:
_ := $(shell $(MAKE) -C gen testing.env "TEST_FORK=$(strip $(TEST_FORK))")
include gen/testing.env
export
unexport TEST_FORK
endif
test: build
	forge test

clean:
	@$(MAKE) -C gen clean
	forge clean
