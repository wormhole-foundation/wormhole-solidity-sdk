GENEREATORS = chains cctpDomains
chains_TARGET = ../src/constants/Chains.sol
cctpDomains_TARGET = ../src/constants/CCTPDomains.sol

TEST_WRAPPERS = BytesParsing
BytesParsing_BASE_PATH = libraries

fnTestWrapperTarget = ../test/generated/$(1)TestWrapper.sol
TEST_WRAPPER_TARGETS =\
  $(foreach wrapper, $(TEST_WRAPPERS), $(call fnTestWrapperTarget,$(wrapper)))

.PHONY: generate $(GENEREATORS) force

generate: $(GENEREATORS) $(TEST_WRAPPER_TARGETS)

$(GENEREATORS): node_modules
	npx ts-node $@.ts > $($@_TARGET)

node_modules:
	npm install

define fnTestWrapperRule
$(call fnTestWrapperTarget,$(1)): ../src/$($(1)_BASE_PATH)/$(1).sol
	npx ts-node libraryTestWrapper.ts $($(1)_BASE_PATH)/$(1) > $(call fnTestWrapperTarget,$(1))
endef
$(foreach wrapper,$(TEST_WRAPPERS),$(eval $(call fnTestWrapperRule,$(wrapper))))


