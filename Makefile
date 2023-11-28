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
deploy-seam-base-testnet		:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${BASE_GOERLI_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_GOERLI_VERIFIER_URL} -vvvv
deploy-seam-tenderly			:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast -vvvv
deploy-seam-base-mainnet		:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

upgrade-seam-base-testnet		:; forge script script/SeamUpgrade.s.sol:SeamUpgradeScript --force --rpc-url ${BASE_GOERLI_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_GOERLI_VERIFIER_URL} -vvvv
upgrade-seam-base-mainnet		:; forge script script/SeamUpgrade.s.sol:SeamUpgradeScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-vesting-wallet-base-mainnet :; forge script script/SeamVestingWallet.s.sol:SeamVestingWalletDeployScript --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv
deploy-vesting-wallet-base-tenderly :; forge script script/SeamVestingWallet.s.sol:SeamVestingWalletDeployScript --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-full-gov-base-testnet	:; forge script script/SeamFullGovernanceDeploy.s.sol:SeamFullGovernanceDeploy --force --rpc-url ${BASE_GOERLI_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_GOERLI_VERIFIER_URL} -vvvv
deploy-full-gov-base-mainnet	:; forge script script/SeamFullGovernanceDeploy.s.sol:SeamFullGovernanceDeploy --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-seam-l1-eth-testnet		:; forge script script/SeamL1Deploy.s.sol:SeamL1DeployScript --force --evm-version shanghai --rpc-url ${ETH_TESTNET_RPC_URL} --slow --broadcast --verify --delay 5 -vvvv
deploy-seam-l1-eth-mainnet		:; forge script script/SeamL1Deploy.s.sol:SeamL1DeployScript --force --evm-version shanghai --rpc-url ${ETH_RPC_URL} --slow --broadcast --verify --delay 5 -vvvv

# verify-contract					:; forge verify-contract 0x4a46Ebdd35B12703717d6F4DfbF5db91E6Ac0660 SeamL1 --watch --chain-id 5 --constructor-args 0x000000000000000000000000fa6d8ee5be770f84fc001d098c4bd604fe01284a0000000000000000000000008c0de778f20e7d25e6e2aac23d5bee1d19deb491000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000085365616d6c65737300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000045345414d00000000000000000000000000000000000000000000000000000000