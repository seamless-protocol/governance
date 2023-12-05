# Governance Spec

## Overview

This document outlines the governance process of Seamless Protocol, which is subject to change by the governance process itself. Onchain governance for Seamless Protocol is on [Base](https://base.org/).

The governance system is implemented using OpenZeppelin contracts, which are themselves based on Compound’s governance system.

## Process

1. Discuss proposal with the community in [Discourse](https://seamlessprotocol.discourse.group/).
2. Proposal is submitted on Snapshot Labs for offchain temperature check.
3. If the proposal threshold is met, the proposal is submitted onchain (this submission includes the code to be executed onchain by governor and timelock).
   - Voting begins after 2 day window
4. Voting period begins and lasts for a defined length depending on the category of the proposal (between 3-10 days). The snapshot for voting power occurs at the beginning of the voting period. Voting power (including delegation) for this proposal may not change after this snapshot.
5. If quorum is met AND vote passes, the timelock automatically executes the proposal code onchain. The timelock execution delay depends on the proposal category and ranges from 2-5 days.
   - If quorum is not met OR quorum is met but vote does not pass, the submitted proposal fails and the code is not executed.

### Governance Thresholds

#### Short/Protocol changes

- Quorum: 1,5% of token supply (For, No, and Abstain votes count toward quorum)
  - SEAM total supply is 100,000,000 so quorum is 1,500,000
- Vote differential: Number of For votes > Number of Against votes
- Timelock: 2 days (48 hours)
- Proposal voting power requirement: 0.2% of token supply
- Voting period: 3 days
- Examples: risk parameter changes, adding new asset markets, SEAM token emissions rate, etc.

#### Long/Governance changes

- Quorum: 1,5% of token supply (For, No, and Abstain votes count toward quorum)
  - SEAM total supply is 100,000,000 so quorum is 1,500,000
- Vote differential: Number of For votes > 2 x Number of Against votes
- Timelock: 5 days (120 hours)
- Proposal voting power requirement: 0.2% of token supply
- Voting period: 10 days
- Examples: changes to quorum thresholds, etc.

The calculated total supply used in quorum thresholds is the SEAM token total supply. All time periods are denominated in seconds, not block numbers.

### Governance Guardians

A community “Governance Guardian” multisig will have the ability to veto governance proposals that are deemed malicious to the protocol and community health. This can occur during the final timelock execution phase and is limited to vetoing proposals only (not passing proposals or adjusting other types of parameters).

The community Governance Guardian multisig will utilize GnosisSafe and be a “3 of 5” multisig, composed of community members and contributors ranging from multiple entities. Future adjustments to the Governance Guardian multisig (such as number of signers, thresholds or key holders) will be determined and voted on through governance and implemented by the Governance Guardian multisig.

Governance Guardians commit to industry best practices, such as utilizing secure hardware wallets. The initial Governance Guardians from the community are:

- Brandon Iles
- Chaos Labs
- Daryl Hok
- Mark Toda
- Richy Qiao
- Wesley Frederickson

## Voting Power

- SEAM is an ERC20 token that entitles a user to participate in onchain governance. SEAM balance is voting power.
- Voting power must be delegated to be used, either to self or to another address (EOA or smart contract).
  - Voting power can only be delegated to a single address at once and all voting power (balance) is delegated.
- Voting power for a specific proposal is determined by a snapshot of voting power state onchain at the time when the proposal voting period begins.

### SEAM Governance Token

SEAM is only earned by using the protocol and performing behaviors that push the community and protocol forward. i.e.: emissions or airdrop determined by governance.

#### Emissions

SEAM supply is unlocked for emissions at a defined rate. These unlocked emissions will be distributed to promote a strong Seamless Protocol community as defined by governance and will follow an emission schedule that will be outlined initially.

### Delegation

Each unit of voting power can be delegated to any address, including smart contracts. A smart contract may implement its own governance rules for use of the voting power delegated to it. One such governance process may be the execution of an offchain governance process.

## Governance Actions

1. Propose and vote on changes to the protocol.
2. Propose and vote on changes to governance itself.
3. Propose and vote on SEAM token emissions.

## Emergency Procedures (Protocol Guardians)

_(not to be confused with the Governance Guardians, as these are two completely distinct and unrelated bodies)_

To prevent negative impacts to the protocol and its users, governance will appoint Protocol Guardians, which have the authority to make scoped emergency changes to the protocol that are too time sensitive to run through the governance process. The actions that can be taken by these “Protocol Guardians” are determined by governance and are limited in scope. The role of Protocol Guardians is to prevent damage to the protocol and its users until the governance process can implement more significant changes to resolve issues. For example, a Protocol Guardian may be granted permission to pause protocol contract activity if a security issue or major bug is discovered. This pause would last until governance can approve and deploy a remedy.

Protocol Guardians are smart contracts wallets (e.g.: multisig) that are configured by governance. For example, governance would appoint members of the community to act as signers on a guardian multisig.

## Implementation Notes

Onchain governance contracts will be based on the OpenZeppelin v5 governance contracts [ref](https://docs.openzeppelin.com/contracts/5.x/governance).
