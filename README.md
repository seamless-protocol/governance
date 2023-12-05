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
| EscrowSEAM     | `0x43Fde98A596B26F3524c806C0BB75960CE7273Ff` | `0xCc8D5c51e022aEa830b6B1f63Bc84dF449F692F5` |
| Timelock short | `0x965bb7cB17ef3685366AF223924C545AaFB2baEE` | `0x802D5Bea8e1c49eA458622C6CBB4cc5accf0128c` |
| Governor short | `0x4D008d500013e180e48791a2A8Aa767EEf662aa0` | `0x7F9576436Dc83E42b500ECA45f1Dc673B0257B42` |
| Timelock long  | `0x80faf3A9202De4FFa6E8849021181252370e5052` | `0x04277F591C8c6876a96898d7e99B3D8f5Fe2cbd9` |
| Governor long  | `0x2A4CC3F5FF8d25086BB493B5c0d1d50c4037c461` | `0x2a8491354b023da5378b3Fe1Da86F1cd2089412d` |

### Ethereum Testnet (Goerli)

SEAML1: `0x4a46Ebdd35B12703717d6F4DfbF5db91E6Ac0660`

### Base Mainnet

| Contract | Proxy address                                | Implementation address                       |
| -------- | -------------------------------------------- | -------------------------------------------- |
| SEAM     | `0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85` | `0x213fB4BBE3BfB56d967459BdB2749b4597513d24` |

### Ethereum Mainnet

SeamL1: `0x6b66ccd1340c479B07B390d326eaDCbb84E726Ba`
