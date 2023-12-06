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

### Base Testnet (Goerli)

| Contract       | Proxy address                                | Implementation address                       |
| -------------- | -------------------------------------------- | -------------------------------------------- |
| SEAM           | `0x8c0dE778f20e7D25E6E2AAc23d5Bee1d19Deb491` | `0x0F2B5682562E3743F68D106CDf9512a9cd70e62e` |
| EscrowSEAM     | `0xcAFf1eb3eF39D665340c94c4C20660613D66c691` | `0x38405c502676152d4D4b9c04177b2b500b53202E` |
| Timelock short | `0x3456B1781A86df123aa9dCEeFA818E1E68a25a4E` | `0x341e372C091c93f73b451BDa20A3147A776fB3eb` |
| Governor short | `0xa83325c6c4E4D8FC07b1d79E93ff66Af7533B2Bf` | `0xE66d871C14af041cd7a77bfBc4E372dd1ec62BB8` |
| Timelock long  | `0x565504FcD4A1552990CFC5569548e0929571A9E4` | `0x80e887428cCa630F75a2452D27AA9805E9D5a1d8` |
| Governor long  | `0x42159A640De060a36fe574c2b336Ef2a752B1e88` | `0x28a43359BD4aB030d5884b3074B3d3418697Ab03` |

### Ethereum Testnet (Goerli)

SEAML1: `0x4a46Ebdd35B12703717d6F4DfbF5db91E6Ac0660`

### Base Mainnet

| Contract | Proxy address                                | Implementation address                       |
| -------- | -------------------------------------------- | -------------------------------------------- |
| SEAM     | `0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85` | `0x213fB4BBE3BfB56d967459BdB2749b4597513d24` |

### Ethereum Mainnet

SeamL1: `0x6b66ccd1340c479B07B390d326eaDCbb84E726Ba`
