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
| Contract | Proxy address | Implementation address |
|---|---|---|
|SEAM|`0x8c0dE778f20e7D25E6E2AAc23d5Bee1d19Deb491`|`0x0F2B5682562E3743F68D106CDf9512a9cd70e62e`|
|EscrowSEAM|`0x6B3D691C6E826f10f17e0be1cCf9694b6B22136E`|`0xE74AD7C5b4d60910D0EAe45519e6D79FcC2Ed14f`|
|Timelock short|`0x1368577B51AF3b6C8cD77930Ee7edEeD3a43692E`|`0x7231988D331d54bEeD7D13dBb1b0787b2baC33aE`|
|Governor short|`0xB054EeCDab00C0014C88403A933F6625a8b66eeB`|`0x014ACf0eb966E4dC3ffdfE7B3852AFD5bcD69BF7`|
|Timelock long|`0x4347a5445E3c33DBdb8414bC525C3dEA2A7F9296`|`0x94cBDAe2D67bad72bFCab48D429365cC819BaA3e`|
|Governor long|`0x4A8d272ce2248f18c0EDe5969e365172C452EdbF`|`0x0Aa5E51c34bfc9509A264a48E842591cAC2c8B14`|

### Ethereum Testnet (Goerli)
SEAML1: `0x4a46Ebdd35B12703717d6F4DfbF5db91E6Ac0660`

### Base Mainnet
| Contract | Proxy address | Implementation address |
|---|---|---|
|SEAM|`0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85`|`0x213fB4BBE3BfB56d967459BdB2749b4597513d24`|

### Ethereum Mainnet
SeamL1: `0x6b66ccd1340c479B07B390d326eaDCbb84E726Ba`