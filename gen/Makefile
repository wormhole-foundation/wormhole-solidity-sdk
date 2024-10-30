GENERATORS = chains cctpDomains
chains_TARGET = constants/Chains.sol
cctpDomains_TARGET = constants/CCTPDomains.sol

fnGeneratorTarget = ../src/$($(1)_TARGET)
GENERATOR_TARGETS = $(foreach generator,$(GENERATORS),$(call fnGeneratorTarget,$(generator)))

TEST_WRAPPERS = BytesParsing QueryResponse

fnTestWrapperTarget = ../test/generated/$(1)TestWrapper.sol
TEST_WRAPPER_TARGETS =\
  $(foreach wrapper,$(TEST_WRAPPERS),$(call fnTestWrapperTarget,$(wrapper)))

.DEFAULT_GOAL = build
.PHONY: build clean FORCE

build: $(GENERATOR_TARGETS) $(TEST_WRAPPER_TARGETS)

clean:
	rm -rf node_modules fork_changed testing.env

FORCE:

node_modules:
	npm i

define ruleGenerator
$(call fnGeneratorTarget,$(1)): node_modules $(1).ts
	npx ts-node $(1).ts > $$@
endef
$(foreach generator,$(GENERATORS),$(eval $(call ruleGenerator,$(generator))))

define ruleTestWrapper
$(call fnTestWrapperTarget,$(1)): ../src/libraries/$(1).sol libraryTestWrapper.ts
	npx ts-node libraryTestWrapper.ts libraries/$(1) > $$@
endef
$(foreach wrapper,$(TEST_WRAPPERS),$(eval $(call ruleTestWrapper,$(wrapper))))

ifneq ($(TEST_FORK), $(shell cat fork_changed 2>/dev/null))
#if a different chain/network for testing was supplied last time then force an update
fork_changed: FORCE
endif

testing.env: node_modules fork_changed testingEnv.ts
	@echo "Generating testing.env for $(TEST_FORK)"
	npx ts-node testingEnv.ts $(TEST_FORK) > $@

fork_changed:
	@echo $(TEST_FORK) > fork_changed
