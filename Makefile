# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

.PHONY: test clean

# Build & test
build                   :; forge build
coverage                :; forge coverage
gas                     :; forge test --gas-report
gas-check               :; forge snapshot --check --tolerance 1
snapshot                :; forge snapshot
clean                   :; forge clean
fmt                     :; forge fmt
test                    :; forge test -vvv

# Deploy
deploy-base-testnet		:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${BASE_GOERLI_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv
deploy-base-tenderly	:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast -vvvv
deploy-base-mainnet		:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast -vvvv