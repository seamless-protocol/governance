# Governance Specs

## Overview

This document outlines the governance of the Seamless protocol, it is subject to change by the governance process itself. On-chain governance for Seamless protocol is on Ethereum mainnet.

## Process

0. Discuss proposal with the community
1. Proposal is submitted on Snapshot labs for off-chain temperature check
2. Proposal is submitted on chain (including the code to be executed on chain by governor and timelock)
    - Voting begins after a 2 day delay
3. Voting
    - Snapshot of voting power occurs at the begining of the voting period. Voting power (including delegation) for this proposal may not change after this snapshot.
4. Timelock
    - Timelock executes proposal code on chain (including passing execution to a bridge contract)
5. Bridge
6. Destination chain timelock
    - Execution of proposal call data after 1 day

### Governance Thresholds

- Protocol changes
    - Quorum: 1% of token supply
    - Vote differential: Greater than 50% For
    - Timelock: 2 days
    - Proposal voting power requirement: 0.5% of token supply
    - Voting period: 3 days
    - Timelock: 1 day
- Governance changes
    - Quorum: 10% of token supply
    - Vote differential: Greater than 65% For
    - Timelock: 5 days
    - Proposal voting power requirement: 2% of token supply
    - Voting period: 10 days
    - Timelock: 3 days

## Voting Power

- Voting power is determined exclusively by the amount of governance tokens that have been delegated to an address (wallet or smart contract).
- Voting power for a specific proposal is determined by a snapshot of voting power state on chain.
- Voting power and proposal power must be maintained until execution of a proposal on chain.

### Gov Token

- Non-transferable. Only earned by using the protocol and performing behaviours that push the community and protocol forward. i.e.: emissions or airdrop determined by governance.

## Delegation

Each unit of governance token held can be delegated to any address, including smart contracts. A smart contract may implement its own governance rules for use of the voting power delegated to it. One such governance process may be the execution of an off chain governance process.

*Note:* It is in the best interest of protocol governance that users do not centralize delegation to small number of governance delegates (including off-chain delegates). Concentration/centralization of voting power poses systemic risks to protocol governance.

### Off-chain Delegates

Governance participation in the form of active on chain voting can be expensive, especially on Ethereum mainnet. We recognize that many community members would like to participate actively in on chain governance but do not due to the associated gas costs. We recommend that users choose a delegate that implements a robust off chain governance system in this case.

Off-chain delegates may choose to use tools like Snapshot Labs to hold off-chain votes for users that have delegated their voting power on chain to them. The result of this off-chain governance process should be executed on chain with the delegate contract's voting power. 

## Governance Actions

1. Propose and vote on changes to the protocol
2. Propose and vote on changes to governance itself
3. Propose and vote on governance token emissions

## Emergency procedures

To prevent negative impacts to the protocol and its users, governance appoints guardians, which have the authority to make scoped emergency changes to the protocol that are too time senstive to run through the governance process. The actions that can be taken by guardians are pre-determined by governance and especially are not all encompassing. The role of guardians is to prevent damage to the protocol and its users until the governance process can implement more significant changes to resolve issues. For example, a guardian may be granted permission to pause protocol contract activity if a security issue or major bug is discovered, this pause would last until governance can approve and deploy a remedy.

Guardians are smart contracts wallets (e.g.: multisig) that are configured by governance. For example, governance would appoint members of the community to act as signers on the guardian multisig.

# Possible Improvements

- Each delegate has a max voting power they can receive. Beyond this max the voting power of is reduced quadraticaly (i.e.: `votingpower = min(voting_power_threshold, voting_power_delegated) + sqrt(voting_power_threshold - voting_power_delegated)`).
- As a token holder you can delegate a maximum number for tokens to a single delegate (unless that delegate is yourself).