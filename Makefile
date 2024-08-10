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
deploy-seam-base-testnet		:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${BASE_TESTNET_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_TESTNET_VERIFIER_URL} -vvvv
deploy-seam-tenderly			:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast -vvvv
deploy-seam-base-mainnet		:; forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

upgrade-seam-base-testnet		:; forge script script/SeamUpgrade.s.sol:SeamUpgradeScript --force --rpc-url ${BASE_TESTNET_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_TESTNET_VERIFIER_URL} -vvvv
upgrade-seam-base-mainnet		:; forge script script/SeamUpgrade.s.sol:SeamUpgradeScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-vesting-wallet-base-mainnet :; forge script script/SeamVestingWallet.s.sol:SeamVestingWalletDeployScript --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv
deploy-vesting-wallet-base-tenderly :; forge script script/SeamVestingWallet.s.sol:SeamVestingWalletDeployScript --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast -vvvv

deploy-full-gov-base-testnet	:; forge script script/SeamFullGovernanceDeploy.s.sol:SeamFullGovernanceDeploy --force --rpc-url ${BASE_TESTNET_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_TESTNET_VERIFIER_URL} -vvvv
deploy-full-gov-base-mainnet	:; forge script script/SeamFullGovernanceDeploy.s.sol:SeamFullGovernanceDeploy --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-emission-manager-base-testnet	:; forge script script/SeamEmissionManagerDeploy.s.sol:SeamEmissionManagerDeploy --force --rpc-url ${BASE_TESTNET_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_TESTNET_VERIFIER_URL} -vvvv
deploy-emission-manager-base-mainnet	:; forge script script/SeamEmissionManagerDeploy.s.sol:SeamEmissionManagerDeploy --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-airdrop-base-testnet	:; forge script script/SeamAirdropDeploy.s.sol:SeamAirdropDeploy --force --rpc-url ${BASE_TESTNET_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${BASE_TESTNET_VERIFIER_URL} -vvvv
deploy-airdrop-base-mainnet	:; forge script script/SeamAirdropDeploy.s.sol:SeamAirdropDeploy --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-seam-l1-eth-testnet		:; forge script script/SeamL1Deploy.s.sol:SeamL1DeployScript --force --evm-version shanghai --rpc-url ${ETH_TESTNET_RPC_URL} --slow --broadcast --verify --delay 5 -vvvv
deploy-seam-l1-eth-mainnet		:; forge script script/SeamL1Deploy.s.sol:SeamL1DeployScript --force --evm-version shanghai --rpc-url ${ETH_RPC_URL} --slow --broadcast --verify --delay 5 -vvvv

deploy-seam-transfer-strategy-base-mainnet	:; forge script script/SeamTransferStrategy.s.sol:SeamTransferStrategyScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv

deploy-escrow-seam-transfer-strategy-base-mainnet	:; forge script script/EscrowSeamTransferStrategy.s.sol:EscrowSeamTransferStrategyScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv
deploy-escrow-seam-transfer-strategy-tenderly	:; forge script script/EscrowSeamTransferStrategy.s.sol:EscrowSeamTransferStrategyScript --force --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast -vvvv

deploy-erc20-transfer-strategy-base-mainnet	:; forge script script/ERC20TransferStrategy.s.sol:ERC20TransferStrategyScript --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv
deploy-erc20-transfer-strategy-tenderly		:; forge script script/ERC20TransferStrategy.s.sol:ERC20TransferStrategyScript --force --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast -vvvv

deploy-escrow-seam-implementation-base-mainnet	:; forge script script/EscrowSeamImplementationDeploy.s.sol:EscrowSeamImplementationDeploy --force --rpc-url ${BASE_RPC_URL} --slow --broadcast --verify --delay 5 --verifier-url ${VERIFIER_URL} -vvvv
deploy-escrow-seam-implementation-tenderly		:; forge script script/EscrowSeamImplementationDeploy.s.sol:EscrowSeamImplementationDeploy --force --rpc-url ${TENDERLY_FORK_RPC_URL} --slow --broadcast -vvvv

