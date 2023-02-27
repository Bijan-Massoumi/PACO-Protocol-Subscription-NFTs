.PHONY: test

test:
	forge test --fork-url $(ETH_RPC) -vv 