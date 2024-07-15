// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "../../src/Seam.sol";
import {SeamGovernor} from "../../src/SeamGovernor.sol";
import {Constants} from "../../src/library/Constants.sol";
import {EscrowSeamTransferStrategy} from "../../src/transfer-strategies/EscrowSeamTransferStrategy.sol";
import {RewardsController} from "aave-v3-periphery/contracts/rewards/RewardsController.sol";
import {ITransferStrategyBase} from "aave-v3-periphery/contracts/rewards/interfaces/ITransferStrategyBase.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";

contract EsSeamTransferStrategyChangeTest is Test {
    EscrowSeamTransferStrategy public constant currentEscrowSeamTransferStrategy =
        EscrowSeamTransferStrategy(0x2181be388ced00754E7c1Ee33DBcF78397DD89aC);
    IRewardsController public constant rewardsController = IRewardsController(Constants.REWARDS_CONTROLLER_ADDRESS);

    // Any address can be used here, it does not need to be a real user because function will revert every time esSEAM rewards are 0
    // But here we use a real user address to make it more realistic
    address public constant BUGGED_USER = 0xEFCb4E944a84140c405efBd2186Fb4aA6bB7C405;

    function setUp() public {
        vm.createSelectFork(vm.envString("TENDERLY_FORK_RPC_URL"));
    }

    function testChange() public {
        vm.expectRevert();
        _tryClaimRewards();

        _changeEsSeamTransferStrategy();

        // Check that claiming of rewards will not revert
        _tryClaimRewards();
    }

    function _tryClaimRewards() internal {
        vm.startPrank(BUGGED_USER);

        address[] memory tokens = new address[](1);
        tokens[0] = Constants.sBRETT_ADDRESS;

        rewardsController.claimAllRewardsToSelf(tokens);

        vm.stopPrank();
    }

    function _changeEsSeamTransferStrategy() internal {
        address newEscrowSeamTransferStrategy = address(
            new EscrowSeamTransferStrategy(
                currentEscrowSeamTransferStrategy.seam(),
                currentEscrowSeamTransferStrategy.escrowSeam(),
                currentEscrowSeamTransferStrategy.getIncentivesController(),
                currentEscrowSeamTransferStrategy.getRewardsAdmin()
            )
        );

        vm.startPrank(rewardsController.EMISSION_MANAGER());

        rewardsController.setTransferStrategy(
            Constants.ESCROW_SEAM_ADDRESS, ITransferStrategyBase(newEscrowSeamTransferStrategy)
        );

        vm.stopPrank();
    }
}
