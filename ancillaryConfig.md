# Safety Module Ancillary Configuration

## overview

This document will outline deployment procedures, related contracts, and necessary steps/permissions to launch the safety module.

## 1. Deploy stkSEAM 
The first step is to deploy stkSEAM using the StakedToken.sol contract. The initializer requires the SEAM token address, an admin address, name and symbol, and then a cooldown period and withdrawal window.

## 2. Deploy RewardKeeper
The next step is the rewardKeeper. The initializer requires:
- Seamless Pool contract address (pool v3)
- admin wallet
- stkSEAM address
- an oracle contract address that conforms to IEACAggregatorPolicy (i.e. 0x602823807C919A92B63cF5C126387c4759976072)
- The asset treasury contract address (0x982F3A0e3183896f9970b8A9Ea6B69Cd53AF1089)

## 3. Deploy RewardsController
We now deploy the RewardsController.sol contract. Directly from aave-v3-periphery fork by Seamless. This contract takes 1 constructor param, the reward keeper address (from above).

## 4. Set RewardsController address on Reward Keeper
The admin of the Reward Keeper must now call "setRewardsController" and pass in the address of the RewardsController contract.

## 5. Set RewardsController address on stkSEAM
The admin of stkSEAM must now call "setController" and pass in the address of the RewardsController contract.

## 6. Asset treasury must grant RewardKeeper full allowance for all sTokens
The admin of the Asset Treasury (CA: 0x982F3A0e3183896f9970b8A9Ea6B69Cd53AF1089) must call "approve" for each sToken and grant max approval to the RewardKeeper address. This can be achieved by pulling the full list of assets (pool.getReservesList) and then looping through the list. In the loop, we call pool.getReserveData (passing in the current asset address) to get the sToken address. We can then call "approve" on the treasury to grant the allowance. A script for this action will be provided (SafetyModuleTreasuryApproval.s.sol)