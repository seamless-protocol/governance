# Token

## How to Test

`forge test`

## How to Deploy

1. `cp .env.example .env` and fill in values

2. Deploy
Base Testnet: `source .env && forge script script/TokenDeploy.s.sol:TokenDeployScript --rpc-url $BASE_GOERLI_RPC_URL --broadcast --verify -vvvv`
Base Mainnet: `source .env && forge script script/TokenDeploy.s.sol:TokenDeployScript --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv`

3. Verify (if manual verification required)
`forge verify-contract --chain-id {chain_id_here}`