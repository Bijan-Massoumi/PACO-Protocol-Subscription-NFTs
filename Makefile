.PHONY: test

test:
	forge test --fork-url $(RPC) -vv 
