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
Base Testnet: `source .env && forge script script/TokenDeploy.s.sol:TokenDeployScript --force --rpc-url $BASE_GOERLI_RPC_URL --broadcast --verify --delay 5 --verifier-url $VERIFIER_URL -vvvv`
Base Mainnet: `source .env && forge script script/TokenDeploy.s.sol:TokenDeployScript --force --rpc-url $BASE_RPC_URL --broadcast --verify --delay 5 --verifier-url $VERIFIER_URL -vvvv`

## Deployment Addresses

### Base Testnet
proxy: `0x603b3d3851020559d0e684e7e77d4d978a317d9b`
implementation: `0x0768b63c1e80082D7B8310470f6a1e6FcB08408F`