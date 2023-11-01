# Governance

[![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## How to Compile

`make build`

## How to Lint

`make fmt`

## How to Test

`make test`

## How to Deploy

1. `cp .env.example .env` and fill in values

2. Update constants in `script/TokenDeploy.s.sol` if necessary.

3. Deploy

Base Testnet: `make deploy-base-testnet`

Base Mainnet: `make deploy-base-mainnet`

Base Tenderly Fork: `make deploy-base-tenderly`

## Deployment Addresses

### Base Testnet
proxy: `0xF452087775c75149260948bDa26253297F6B40a8`
implementation: `0x5BdB2d6671E28D3B84910a0c394250F7285F5815`

### Base Mainnet
proxy: `0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85`
implementation: `0x213fB4BBE3BfB56d967459BdB2749b4597513d24`