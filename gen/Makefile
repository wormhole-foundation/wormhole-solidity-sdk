GENERATORS = chains cctpDomains chainConsts
chains_TARGET = constants/Chains.sol
cctpDomains_TARGET = constants/CctpDomains.sol
chainConsts_TARGET = testing/ChainConsts.sol

fnGeneratorTarget = ../src/$($(1)_TARGET)
GENERATOR_TARGETS = $(foreach generator,$(GENERATORS),$(call fnGeneratorTarget,$(generator)))

TEST_WRAPPERS = BytesParsing QueryResponse VaaLib TokenBridgeMessages CctpMessages ReplayProtection

fnTestWrapperTarget = ../test/generated/$(1)TestWrapper.sol
TEST_WRAPPER_TARGETS =\
  $(foreach wrapper,$(TEST_WRAPPERS),$(call fnTestWrapperTarget,$(wrapper)))

.DEFAULT_GOAL = build
.PHONY: build clean FORCE

build: $(GENERATOR_TARGETS) $(TEST_WRAPPER_TARGETS)

clean:
	rm -rf node_modules fork_changed

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
