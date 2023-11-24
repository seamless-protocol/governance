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
test                    :; forge test -vvvv --gas-report

# Deploy
deploy-seam-testnet		:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${BASE_GOERLI_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_GOERLI_VERIFIER_URL} -vvvv
deploy-seam-tenderly	:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast -vvvv
deploy-seam-mainnet		:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

upgrade-seam-testnet	:; forge script script/SeamUpgrade.s.sol:SeamUpgradeScript --force --rpc-url ${BASE_GOERLI_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_GOERLI_VERIFIER_URL} -vvvv
upgrade-seam-mainnet	:; forge script script/SeamUpgrade.s.sol:SeamUpgradeScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-vesting-wallet-mainnet :; forge script script/SeamVestingWallet.s.sol:SeamVestingWalletDeployScript --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv
deploy-vesting-wallet-tenderly :; forge script script/SeamVestingWallet.s.sol:SeamVestingWalletDeployScript --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-full-gov-testnet	:; forge script script/SeamFullGovernanceDeploy.s.sol:SeamFullGovernanceDeploy --force --rpc-url ${BASE_GOERLI_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_GOERLI_VERIFIER_URL} -vvvv
deploy-full-gov-mainnet	:; forge script script/SeamFullGovernanceDeploy.s.sol:SeamFullGovernanceDeploy --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv
