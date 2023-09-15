# Token

[![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## How to Compile

`forge build`

## How to Lint

`forge fmt`

## How to Test

`forge test`

## How to Deploy

1. `cp .env.example .env` and fill in values

2. Update constants in `script/TokenDeploy.s.sol` if necessary.

3. Deploy
Base Testnet: `source .env && forge script script/SeamTokenDeploy.s.sol:SeamTokenDeployScript --force --rpc-url $BASE_GOERLI_RPC_URL --slow --broadcast --verify --delay 5 --verifier-url $VERIFIER_URL -vvvv`
Base Mainnet: `source .env && forge script script/SeamTokenDeploy.s.sol:SeamTokenDeployScript --force --rpc-url $BASE_RPC_URL --slow --broadcast --verify --delay 5 --verifier-url $VERIFIER_URL -vvvv`
Base Tenderly Fork: `source .env && forge script script/SeamTokenDeploy.s.sol:SeamTokenDeployScript --force --rpc-url $TENDERLY_FORK_RPC_URL --slow --broadcast -vvvv`

## Deployment Addresses

### Base Testnet
proxy: `0xB2204C80d9570F29586d0648575b2689B1e9d9C5`
implementation: `0x91F2E020fa28ca2955Eb01C5d6316E014394336C`

### Base Mainnet
proxy: `0xA6D3fce31854049398EB47cF9a995ee871450F98`
implementation: `0x4311dC38e44F225EdC38eD5A081715f7B7189134`