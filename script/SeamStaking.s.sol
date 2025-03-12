// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InitializableAdminUpgradeabilityProxy} from
    "aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";
import {RewardsController} from "aave-v3-periphery/contracts/rewards/RewardsController.sol";
import {StakedToken} from "../src/StakedToken.sol";
import {FeeKeeper} from "../src/FeeKeeper.sol";
import {ERC20BalanceSplitterTwoPayee} from "../src/ERC20BalanceSplitterTwoPayee.sol";
import {Constants} from "../src/library/Constants.sol";
import {IFeeSource} from "../src/interfaces/IFeeSource.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract SeamStaking is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        (FeeKeeper feeKeeper, StakedToken stkToken,) = _deployStakedTokenAndDependencies(deployerAddress);

        _deployFeeSplitters(feeKeeper);

        _assignRolesToGovernance(stkToken, feeKeeper, deployerAddress);

        vm.stopBroadcast();
    }

    function _deployStakedTokenAndDependencies(address deployerAddress)
        internal
        returns (FeeKeeper feeKeeper, StakedToken stkToken, RewardsController rewardsController)
    {
        StakedToken stakedTokenImplementation = new StakedToken();
        ERC1967Proxy stakedTokenProxy = new ERC1967Proxy(
            address(stakedTokenImplementation),
            abi.encodeWithSelector(
                StakedToken.initialize.selector,
                Constants.SEAM_ADDRESS,
                deployerAddress,
                "Staked SEAM",
                "stkSEAM",
                7 days,
                1 days
            )
        );
        stkToken = StakedToken(address(stakedTokenProxy));
        console.log(
            "Deployed StakedToken proxy to: ",
            address(stakedTokenProxy),
            " implementation: ",
            address(stakedTokenImplementation)
        );

        FeeKeeper feeKeeperImplementation = new FeeKeeper();
        ERC1967Proxy feeKeeperProxy = new ERC1967Proxy(
            address(feeKeeperImplementation),
            abi.encodeWithSelector(
                FeeKeeper.initialize.selector, deployerAddress, address(stkToken), Constants.ORACLE_PLACEHOLDER
            )
        );
        feeKeeper = FeeKeeper(address(feeKeeperProxy));
        console.log(
            "Deployed FeeKeeper to: ", address(feeKeeperProxy), " implementation: ", address(feeKeeperImplementation)
        );

        RewardsController rewardsControllerImplementation = new RewardsController(address(feeKeeper));
        rewardsControllerImplementation.initialize(address(0));

        InitializableAdminUpgradeabilityProxy rewardControllerProxy = new InitializableAdminUpgradeabilityProxy();

        rewardControllerProxy.initialize(
            address(rewardsControllerImplementation),
            Constants.SHORT_TIMELOCK_ADDRESS,
            abi.encodeWithSelector(RewardsController.initialize.selector, address(feeKeeper))
        );

        rewardsController = RewardsController(address(rewardControllerProxy));

        console.log(
            "Deployed RewardsController to: ",
            address(rewardControllerProxy),
            " implementation: ",
            address(rewardsControllerImplementation)
        );

        // set reward controller on stkToken and reward keeper
        feeKeeper.setRewardsController(address(rewardControllerProxy));
        stkToken.setController(address(rewardControllerProxy));
    }

    function _deployFeeSplitters(FeeKeeper feeKeeper)
        internal
        returns (
            ERC20BalanceSplitterTwoPayee usdcSplitter,
            ERC20BalanceSplitterTwoPayee cbbtcSplitter,
            ERC20BalanceSplitterTwoPayee wethSplitter
        )
    {
        usdcSplitter = new ERC20BalanceSplitterTwoPayee(
            address(feeKeeper), Constants.CURATOR_FEE_RECIPIENT, IERC20(Constants.SEAMLESS_USDC_VAULT), 6000
        );

        cbbtcSplitter = new ERC20BalanceSplitterTwoPayee(
            address(feeKeeper), Constants.CURATOR_FEE_RECIPIENT, IERC20(Constants.SEAMLESS_CBBTC_VAULT), 6000
        );

        wethSplitter = new ERC20BalanceSplitterTwoPayee(
            address(feeKeeper), Constants.CURATOR_FEE_RECIPIENT, IERC20(Constants.SEAMLESS_WETH_VAULT), 6000
        );

        // Add fee sources to FeeKeeper
        feeKeeper.addFeeSource(IFeeSource(address(usdcSplitter)));
        feeKeeper.addFeeSource(IFeeSource(address(cbbtcSplitter)));
        feeKeeper.addFeeSource(IFeeSource(address(wethSplitter)));

        console.log("Added fee sources to FeeKeeper:");
        console.log("- USDC Splitter:", address(usdcSplitter));
        console.log("- cbBTC Splitter:", address(cbbtcSplitter));
        console.log("- WETH Splitter:", address(wethSplitter));
    }

    function _assignRolesToGovernance(StakedToken stkToken, FeeKeeper feeKeeper, address deployer) internal {
        stkToken.grantRole(stkToken.DEFAULT_ADMIN_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);
        stkToken.grantRole(stkToken.MANAGER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);
        stkToken.grantRole(stkToken.UPGRADER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);
        stkToken.grantRole(stkToken.PAUSER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);

        stkToken.grantRole(stkToken.PAUSER_ROLE(), Constants.GUARDIAN_WALLET);

        stkToken.renounceRole(stkToken.DEFAULT_ADMIN_ROLE(), deployer);
        stkToken.renounceRole(stkToken.MANAGER_ROLE(), deployer);
        stkToken.renounceRole(stkToken.UPGRADER_ROLE(), deployer);
        stkToken.renounceRole(stkToken.PAUSER_ROLE(), deployer);

        feeKeeper.grantRole(feeKeeper.DEFAULT_ADMIN_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);
        feeKeeper.grantRole(feeKeeper.MANAGER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);
        feeKeeper.grantRole(feeKeeper.UPGRADER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);
        feeKeeper.grantRole(feeKeeper.PAUSER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);
        feeKeeper.grantRole(feeKeeper.REWARD_SETTER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS);

        feeKeeper.grantRole(feeKeeper.REWARD_SETTER_ROLE(), Constants.GUARDIAN_WALLET);
        feeKeeper.grantRole(feeKeeper.PAUSER_ROLE(), Constants.GUARDIAN_WALLET);

        feeKeeper.renounceRole(feeKeeper.DEFAULT_ADMIN_ROLE(), deployer);
        feeKeeper.renounceRole(feeKeeper.MANAGER_ROLE(), deployer);
        feeKeeper.renounceRole(feeKeeper.UPGRADER_ROLE(), deployer);
        feeKeeper.renounceRole(feeKeeper.PAUSER_ROLE(), deployer);
        feeKeeper.renounceRole(feeKeeper.REWARD_SETTER_ROLE(), deployer);
    }
}
