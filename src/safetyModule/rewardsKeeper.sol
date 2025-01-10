// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IEmissionManager} from "@aave/periphery-v3/contracts/rewards/interfaces/IEmissionManager.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {ITransferStrategyBase} from "@aave/periphery-v3/contracts/rewards/interfaces/ITransferStrategyBase.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {RewardKeeperStorage as Storage} from "../storage/RewardKeeperStorage.sol";
import {ERC20TransferStrategy} from "../transfer-strategies/ERC20TransferStrategy.sol";

contract RewardKeeper is UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    event ClaimedAndSetRate(address[] rewards, Storage.Rates[] rates);
    event SetEmissionManager(address emissionManager);
    event SetPool(address pool);
    event SetTreasury(address treasury);
    event SetPeriod(uint256 period);
    event SetRewardAdmin(address newAdmin);
    event AddedToken(address stkToken, uint256 weight);
    event ModifiedToken(address stkToken, uint256 weight);
    event RemovedToken(address stkToken);

    error isZeroAddress(address target);
    error InsufficientTimeElapsed();
    error InvalidPeriod();
    error ArraySizeIncorrect();
    error TokenExists();
    error InvalidWeight();
    error NoTokens();
    
    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address constant ORACLE_MOCK = 0x602823807C919A92B63cF5C126387c4759976072;

    modifier isNotZeroAddress(address target) {
        if (target == address(0)) {
            revert isZeroAddress(target);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    function initialize(address pool, address emissionManager, address initialAdmin, address treasury)
        external
        initializer
    {
        __UUPSUpgradeable_init();
        __Pausable_init();

        Storage.Layout storage $ = Storage.layout();
        $.manager = IEmissionManager(emissionManager);
        $.controller = IRewardsController($.manager.getRewardsController());
        $.pool = IPool(pool);
        $.treasury = treasury;
        $.rewardAdmin = msg.sender;
        $.period = 1 days;
        $.lastClaim = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    function addStkTokens(address[] calldata tokens, uint256[] calldata weights) external onlyRole(MANAGER_ROLE) {
        if (tokens.length != weights.length) revert ArraySizeIncorrect();
        Storage.Layout storage $ = Storage.layout();
        $.arrayLength += tokens.length;
        for (uint256 i; i < tokens.length; i++) {
            if ($.stkTokenPos[tokens[i]] != 0) revert TokenExists();
            if(weights[i] == 0) revert InvalidWeight();

            Storage.StakeTokenInfo memory info = Storage.StakeTokenInfo(tokens[i], weights[i]);
            $.stkTokens.push(info);
            $.stkTokenPos[tokens[i]] = $.stkTokens.length - 1;
            $.totalWeight += weights[i];

            emit AddedToken(tokens[i], weights[i]);
        }
    }

    function removeStkToken(address token) external onlyRole(MANAGER_ROLE) {
        Storage.Layout storage $ = Storage.layout();
        Storage.StakeTokenInfo memory info = $.stkTokens[$.stkTokenPos[token]];
        $.totalWeight = $.totalWeight - info.weight;

        // take last item on the list, place it in subject position
        if ($.stkTokens.length == 0) revert NoTokens();
        uint256 finalPos = $.arrayLength - 1;
        address finalPosAddr = $.stkTokens[finalPos].stkToken;
        $.stkTokens[$.stkTokenPos[token]] = $.stkTokens[finalPos];

        $.stkTokenPos[finalPosAddr] = $.stkTokenPos[token];
        $.stkTokenPos[token] = 0;
        $.arrayLength -= 1;
        delete $.stkTokens[finalPos];

        emit RemovedToken(token);
    }

    function modifyStkToken(address token, uint256 weight) external onlyRole(MANAGER_ROLE) {
        if(weight == 0) revert InvalidWeight();
        Storage.Layout storage $ = Storage.layout();
        Storage.StakeTokenInfo memory info = $.stkTokens[$.stkTokenPos[token]];

        // cleaner to do it this way than to use conditionals
        $.totalWeight = $.totalWeight - info.weight + weight;
        $.stkTokens[$.stkTokenPos[token]].weight = weight;

        emit ModifiedToken(token, weight);

    }
 
    /// @notice EmissionManager requires "rewardToken" address be msg.sender
    /// @dev Could use "ConfigureAssets" instead, but that requires oracle and transferStrategy addresses.
    function claimAndSetRate() external whenNotPaused {
        Storage.Layout storage $ = Storage.layout();
        // check if period has elapsed, update lastClaim
        if ($.lastClaim > block.timestamp - $.previousPeriod) revert InsufficientTimeElapsed();
        $.lastClaim = block.timestamp;
        $.previousPeriod = $.period;

        address[] memory rewardTokens = $.pool.getReservesList();

        // claim rewards
        // assume its coming to this contract for now
        $.pool.mintToTreasury(rewardTokens);

        // get new Emission rates
        Storage.Rates[] memory newRates = new Storage.Rates[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; i++) {
            IERC20 token = IERC20(rewardTokens[i]);

            // withdraw reward tokens
            $.pool.withdraw(rewardTokens[i], type(uint256).max, address(this));

            uint256 balance = token.balanceOf(address(this));

            // there will be dust from rounding here... it can stay in the contract and get accounted for next time.
            uint88 rate = uint88((balance) / $.period);
            uint88[] memory ratesPerAsset = new uint88[]($.arrayLength);
            uint256 totalToTransfer;

            ERC20TransferStrategy transferStrategy =
                ERC20TransferStrategy($.controller.getTransferStrategy(rewardTokens[i]));

            if (address(transferStrategy) == address(0)) {
                RewardsDataTypes.RewardsConfigInput[] memory config = new RewardsDataTypes.RewardsConfigInput[]($.arrayLength);
                
                transferStrategy = new ERC20TransferStrategy(token, address($.controller), $.rewardAdmin);
                for(uint256 k; k < $.arrayLength; k++) {
                    config[k].emissionPerSecond = 0;
                    config[k].totalSupply = token.totalSupply(); // Not sure if this is correct...
                    config[k].distributionEnd = uint32(block.timestamp + $.period);
                    config[k].asset = $.stkTokens[k].stkToken;
                    config[k].reward = rewardTokens[i];
                    config[k].transferStrategy = ITransferStrategyBase(address(transferStrategy));
                    config[k].rewardOracle = IEACAggregatorProxy(ORACLE_MOCK);

                    ratesPerAsset[k] = uint88(rate * $.stkTokens[k].weight / $.totalWeight);
                    totalToTransfer += ratesPerAsset[k] * $.period;
                }
                $.manager.configureAssets(config);
            } else {
                // set distributonEnd here
                for(uint256 k; k < $.arrayLength; k++) {
                    //TODO: Would this ever result in totalToTransfer > balance?
                    ratesPerAsset[k] = uint88(rate * $.stkTokens[k].weight / $.totalWeight);
                    totalToTransfer += ratesPerAsset[k] * $.period;
                    $.manager.setDistributionEnd($.stkTokens[k].stkToken, rewardTokens[i], uint32(block.timestamp + $.period));
                }
                
            }
            newRates[i] = Storage.Rates(ratesPerAsset);
            // ensures dust is not sent.
            token.transfer(address(transferStrategy), totalToTransfer);
        }

        // set emissions per second
        for (uint256 i; i < $.arrayLength; i++) {
            $.manager.setEmissionPerSecond($.stkTokens[i].stkToken, rewardTokens, newRates[i].rates);
        }
        

        emit ClaimedAndSetRate(rewardTokens, newRates);
    }

    function setEmissionManager(address emissionManager)
        external
        isNotZeroAddress(emissionManager)
        onlyRole("MANAGER_ROLE")
    {
        Storage.Layout storage $ = Storage.layout();
        $.manager = IEmissionManager(emissionManager);
        emit SetEmissionManager(emissionManager);
    }

    function setPool(address newPool) external isNotZeroAddress(newPool) onlyRole("MANAGER_ROLE") {
        Storage.Layout storage $ = Storage.layout();
        $.pool = IPool(newPool);
        emit SetPool(newPool);
    }

    function setTreasury(address newTreasury) external isNotZeroAddress(newTreasury) onlyRole("MANAGER_ROLE") {
        Storage.Layout storage $ = Storage.layout();
        $.treasury = newTreasury;
        emit SetPool(newTreasury);
    }

    function setPeriod(uint256 newPeriod) external onlyRole("MANAGER_ROLE") {
        if (newPeriod == 0) revert InvalidPeriod();
        Storage.Layout storage $ = Storage.layout();
        $.period = newPeriod;
        emit SetPeriod(newPeriod);
    }

    function setRewardAdmin(address newAdmin) external isNotZeroAddress(newAdmin) onlyRole("MANAGER_ROLE") {
        Storage.Layout storage $ = Storage.layout();
        $.rewardAdmin = newAdmin;
        emit SetRewardAdmin(newAdmin);
    }
}
