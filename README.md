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
Base Testnet: `source .env && forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url $BASE_GOERLI_RPC_URL --slow --broadcast --verify --delay 5 --verifier-url $VERIFIER_URL -vvvv`
Base Mainnet: `source .env && forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url $BASE_RPC_URL --slow --broadcast --verify --delay 5 --verifier-url $VERIFIER_URL -vvvv`
Base Tenderly Fork: `source .env && forge script script/SeamDeploy.s.sol:SeamDeployScript --force --rpc-url $TENDERLY_FORK_RPC_URL --slow --broadcast -vvvv`

## Deployment Addresses

### Base Testnet
proxy: `0xEA5DBa451b16521cdAedCf8FA307506A05329B05`
implementation: `0xC7565962158D54beCDBE07FC89aE223eeF41f35F`

### Base Mainnet
proxy: `0x07DFE9525A5D274D6f3e906e6A4efA7F066C4926`
implementation: `0x0661DfF721b459510c81C4c737Fa5Ac115E4950D`