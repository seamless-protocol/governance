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

| Contract         | Proxy address                                | Implementation address                       |
| ---------------- | -------------------------------------------- | -------------------------------------------- |
| SEAM             | `0x8c0dE778f20e7D25E6E2AAc23d5Bee1d19Deb491` | `0x0F2B5682562E3743F68D106CDf9512a9cd70e62e` |
| EscrowSEAM       | `0xcAFf1eb3eF39D665340c94c4C20660613D66c691` | `0x38405c502676152d4D4b9c04177b2b500b53202E` |
| Timelock short   | `0x3456B1781A86df123aa9dCEeFA818E1E68a25a4E` | `0x341e372C091c93f73b451BDa20A3147A776fB3eb` |
| Governor short   | `0xa83325c6c4E4D8FC07b1d79E93ff66Af7533B2Bf` | `0xE66d871C14af041cd7a77bfBc4E372dd1ec62BB8` |
| Timelock long    | `0x565504FcD4A1552990CFC5569548e0929571A9E4` | `0x80e887428cCa630F75a2452D27AA9805E9D5a1d8` |
| Governor long    | `0x42159A640De060a36fe574c2b336Ef2a752B1e88` | `0x28a43359BD4aB030d5884b3074B3d3418697Ab03` |
| Emission manager | `0xB1EcA5e7541574798A9e4a58BfE9c78b622138e6` | `0x747e86e46e3E2a87B76da1D87D7E571C6f3D3E04` |
| Airdrop          |                                              | `0xB402A4472103ce81195aEBD68237AbdFDfb8891b` |

### Ethereum Testnet (Goerli)

SEAML1: `0x4a46Ebdd35B12703717d6F4DfbF5db91E6Ac0660`

### Base Testnet (Sepolia)

| Contract         | Proxy address                                | Implementation address                       |
| ---------------- | -------------------------------------------- | -------------------------------------------- |
| SEAM             | `0x178898686F23a50CCAC17962df41395484804a6B` | `0x4a46Ebdd35B12703717d6F4DfbF5db91E6Ac0660` |

### Ethereum Testnet (Sepolia)

SEAML1: `0xF01901ad15fcd248a7175E03c0ecCC0fD1D943Eb`

### Base Mainnet

| Contract                   | Proxy address                                | Implementation address                       |
| -------------------------- | -------------------------------------------- | -------------------------------------------- |
| SEAM                       | `0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85` | `0x57b4b7f830244FC854cD1123ff14AFd4C1AEfd3F` |
| EscrowSEAM                 | `0x998e44232BEF4F8B033e5A5175BDC97F2B10d5e5` | `0x78423BfC5053102A3087DAA978c2117a6809fBB1` |
| Timelock short             | `0x639d2dD24304aC2e6A691d8c1cFf4a2665925fee` | `0x13F5B49217f330167D6350530F6185A75Ab35e6F` |
| Governor short             | `0x8768c789C6df8AF1a92d96dE823b4F80010Db294` | `0xC8A0E02878A4EF18fa260F0968cEcde8Eb607BFc` |
| Timelock long              | `0xA96448469520666EDC351eff7676af2247b16718` | `0xBe170D7D3Cda6E9db39E012D0fE25aB83Fff790d` |
| Governor long              | `0x04faA2826DbB38a7A4E9a5E3dB26b9E389E761B6` | `0x5acB96aAc90BF545500251D1eED10Bf47e996317` |
| Airdrop                    |                                              | `0xB7A6531665c5e2B2d5b9Aa04636847c8F45c702B` |
| Seam Emission Manager 1    | `0x57460DC21bf1574b8e6E00D372b8Ca5Ec41b3955` | `0x03eEEdf76A007Dce47B3a0044D9F0A04BaDD9CFA` |
| Seam Emission Manager 2    | `0x785c979EE8709060b3f71aEf4f2C09229DB90778` | `0x1FDFC3872A70A7af5a818F27bb14fBEA4EE38f9c` |
| SeamTransferStrategy       |                                              | `0x2b1bdeFCe33f34128759f71076eBd62637FD154C` |
| EscrowSeamTransferStrategy |                                              | `0x2181be388ced00754E7c1Ee33DBcF78397DD89aC` |
| ERC20TransferStrategy      |                                              | `0x003D47ddDdb070822B35ae5cc4F0066Cf9E89753` |

### Ethereum Mainnet

SeamL1: `0x6b66ccd1340c479B07B390d326eaDCbb84E726Ba`
