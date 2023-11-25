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
SEAM (proxy): `0x8c0dE778f20e7D25E6E2AAc23d5Bee1d19Deb491`
SEAM Implementation: `0x0F2B5682562E3743F68D106CDf9512a9cd70e62e`

### Ethereum Testnet (Goerli)
SEAML1: `0x4a46Ebdd35B12703717d6F4DfbF5db91E6Ac0660`

### Base Mainnet
SEAM (proxy)proxy: `0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85`
SEAM Implementation: `0x213fB4BBE3BfB56d967459BdB2749b4597513d24`