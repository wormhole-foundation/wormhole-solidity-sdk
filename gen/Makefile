GENEREATORS = chains cctpDomains

chains_PATH = ../src/constants/Chains.sol
cctpDomains_PATH = ../src/constants/CCTPDomains.sol

.PHONY: generate $(GENEREATORS)

generate: $(GENEREATORS)

$(GENEREATORS): node_modules
	npm run --silent $@ > $($@_PATH)

node_modules:
	npm install
