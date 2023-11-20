// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeamEmissionManager} from "src/SeamEmissionManager.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SeamEmissionManagerStorage as Storage} from "src/storage/SeamEmissionManagerStorage.sol";
import {ISeamEmissionManager} from "src/interfaces/ISeamEmissionManager.sol";

contract SeamEmissionManagerTest is Test {
    address immutable seam = address(new ERC20Mock());
    uint256 immutable emissionPerSecond = 1 ether;

    SeamEmissionManager emissionManager;

    function setUp() public {
        SeamEmissionManager implementation = new SeamEmissionManager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                SeamEmissionManager.initialize.selector,
                seam,
                emissionPerSecond,
                address(this),
                address(this)
            )
        );
        emissionManager = SeamEmissionManager(address(proxy));
    }

    function test_SetUp() public {
        assertEq(emissionManager.getSeam(), seam);
        assertEq(emissionManager.getEmissionPerSecond(), emissionPerSecond);
        assertTrue(emissionManager.hasRole(emissionManager.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(emissionManager.hasRole(emissionManager.CLAIMER_ROLE(), address(this)));
    }

    function test_SetEmissionPerSecond() public {
        uint256 newEmissionPerSecond = 2 ether;
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        assertEq(emissionManager.getEmissionPerSecond(), newEmissionPerSecond);
    }

    function testFuzz_SetEmissionPerSecond(uint256 newEmissionPerSecond) public {
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        assertEq(emissionManager.getEmissionPerSecond(), newEmissionPerSecond);
    }

    function testFuzz_SetEmissionPerSecond_RevertIf_NotDefaultAdmin(address caller, uint256 newEmissionPerSecond)
        public
    {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, emissionManager.DEFAULT_ADMIN_ROLE()
            )
        );
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        vm.stopPrank();
    }

    function test_AddNewCategory() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        Storage.CategoryConfig memory category = emissionManager.getCategory(0);
        assertEq(category.description, description);
        assertEq(category.minPercentage, minPercentage);
        assertEq(category.maxPercentage, maxPercentage);
        assertEq(emissionManager.getCategories().length, 1);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 500;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        category = emissionManager.getCategory(1);
        assertEq(category.description, description);
        assertEq(category.minPercentage, minPercentage);
        assertEq(category.maxPercentage, maxPercentage);
        assertEq(emissionManager.getCategories().length, 2);
    }

    function test_AddNewCategory_RevertIf_InvalidPercentage() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 3;

        // Revert because min percentage > max percentage
        vm.expectRevert(ISeamEmissionManager.InvalidPercentage.selector);
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        minPercentage = 4;
        maxPercentage = 4000;

        // Revert because max percentage > BASE_PERCENTAGE
        vm.expectRevert(ISeamEmissionManager.InvalidPercentage.selector);
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);
    }

    function test_RemoveCategory() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 1000;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        // New category should have 100% of emission so removal of first category can be done properly
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 1000;
        uint256[] memory categories = new uint256[](1);
        categories[0] = 1;
        emissionManager.setCategoryPercentages(categories, percentages);

        assertEq(emissionManager.getCategories().length, 2);

        emissionManager.removeCategory(0);

        assertEq(emissionManager.getCategories().length, 1);
        assertEq(emissionManager.getCategory(0).description, description);
    }

    function test_RemoveCategory_RevertIf_InvalidSumOfPercentages() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 0;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 1000;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        // New category should have less then 100% of emission so removal of first category fails due to invalid sum of percentages
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 1;
        percentages[1] = 999;
        uint256[] memory categories = new uint256[](2);
        categories[0] = 0;
        categories[1] = 1;
        emissionManager.setCategoryPercentages(categories, percentages);

        // Revert because sum of percentages is not 100%
        vm.expectRevert(ISeamEmissionManager.InvalidPercentageSum.selector);
        emissionManager.removeCategory(0);
    }

    function test_SetCategoryReceivers() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 1000;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        uint256[] memory categories = new uint256[](2);
        categories[0] = 0;
        categories[1] = 1;
        address[] memory receivers = new address[](2);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        emissionManager.setCategoryReceivers(categories, receivers);

        assertEq(emissionManager.getCategory(0).receiver, receiver1);
        assertEq(emissionManager.getCategory(1).receiver, receiver2);
    }

    function test_SetCategoryReceivers_RevertWhen_ArrayLengthMismatch() public {
        uint256[] memory categories = new uint256[](2);
        address[] memory receivers = new address[](1);

        vm.expectRevert(ISeamEmissionManager.ArrayLengthMismatch.selector);
        emissionManager.setCategoryReceivers(categories, receivers);
    }

    function test_SetCategoryReceivers_RevertWhen_InvalidReceiver() public {
        uint256[] memory categories = new uint256[](1);
        address[] memory receivers = new address[](1);
        receivers[0] = address(0);

        vm.expectRevert(ISeamEmissionManager.InvalidReceiver.selector);
        emissionManager.setCategoryReceivers(categories, receivers);
    }

    function test_SetCategoryPercentages() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 1000;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        uint256[] memory categories = new uint256[](2);
        categories[0] = 0;
        categories[1] = 1;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 100;
        percentages[1] = 900;
        emissionManager.setCategoryPercentages(categories, percentages);

        assertEq(emissionManager.getCategory(0).percentage, 100);
        assertEq(emissionManager.getCategory(1).percentage, 900);
    }

    function test_SetCategoryPercentages_RevertWhen_ArrayLengthMismatch() public {
        uint256[] memory categories = new uint256[](2);
        uint256[] memory percentages = new uint256[](1);

        vm.expectRevert(ISeamEmissionManager.ArrayLengthMismatch.selector);
        emissionManager.setCategoryPercentages(categories, percentages);
    }

    function test_SetCategoryPercentages_RevertWhen_PercetageOutOfBounds() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        uint256[] memory categories = new uint256[](1);
        categories[0] = 0;
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 401;

        // Should fail because percentage is greater than max percentage
        vm.expectRevert(ISeamEmissionManager.PercentageOutOfBounds.selector);
        emissionManager.setCategoryPercentages(categories, percentages);

        percentages[0] = 3;

        // Should fail because percentage is less than min percentage
        vm.expectRevert(ISeamEmissionManager.PercentageOutOfBounds.selector);
        emissionManager.setCategoryPercentages(categories, percentages);
    }

    function test_SetCategoryPercentages_RevertIf_InvalidSumOfPercentages() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 0;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 1000;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        uint256[] memory categories = new uint256[](2);
        categories[0] = 0;
        categories[1] = 1;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 2;
        percentages[1] = 999;

        // Revert because sum of percentages is 100.1% which is not 100%
        vm.expectRevert(ISeamEmissionManager.InvalidPercentageSum.selector);
        emissionManager.setCategoryPercentages(categories, percentages);
    }

    function test_SetCategoryPercentagesAndReceivers() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 1000;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        uint256[] memory categories = new uint256[](2);
        categories[0] = 0;
        categories[1] = 1;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 100;
        percentages[1] = 900;
        address[] memory receivers = new address[](2);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        emissionManager.setCategoryPercetagesAndReceivers(categories, percentages, receivers);

        assertEq(emissionManager.getCategory(0).percentage, 100);
        assertEq(emissionManager.getCategory(1).percentage, 900);
        assertEq(emissionManager.getCategory(0).receiver, receiver1);
        assertEq(emissionManager.getCategory(1).receiver, receiver2);
    }

    function test_SetCategoryPercentagesAndRecievers_RevertWhen_ArrayLengthMismatch() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        uint256[] memory categories = new uint256[](2);
        uint256[] memory percentages = new uint256[](1);
        address[] memory receivers = new address[](1);

        vm.expectRevert(ISeamEmissionManager.ArrayLengthMismatch.selector);
        emissionManager.setCategoryPercetagesAndReceivers(categories, percentages, receivers);
    }

    function test_SetCategoryPercentagesAndReceivers_RevertWhen_InvalidReceiver() public {
        uint256[] memory categories = new uint256[](1);
        categories[0] = 0;
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 100;
        address[] memory receivers = new address[](1);
        receivers[0] = address(0);

        vm.expectRevert(ISeamEmissionManager.InvalidReceiver.selector);
        emissionManager.setCategoryPercetagesAndReceivers(categories, percentages, receivers);
    }

    function test_SetCategoryPercentagesAndReceivers_RevertWhen_PercentageOutOfBounds() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        uint256[] memory categories = new uint256[](1);
        categories[0] = 0;
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 401;
        address[] memory receivers = new address[](1);
        receivers[0] = makeAddr("receiver");

        // Should fail because percentage is greater than max percentage
        vm.expectRevert(ISeamEmissionManager.PercentageOutOfBounds.selector);
        emissionManager.setCategoryPercetagesAndReceivers(categories, percentages, receivers);

        percentages[0] = 3;

        // Should fail because percentage is less than min percentage
        vm.expectRevert(ISeamEmissionManager.PercentageOutOfBounds.selector);
        emissionManager.setCategoryPercetagesAndReceivers(categories, percentages, receivers);
    }

    function test_SetCategoryPercentagesAndReceivers_RevertWhen_InvalidPercentageSum() public {
        string memory description = "ILM LPs";
        uint256 minPercentage = 0;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 1000;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        uint256[] memory categories = new uint256[](2);
        categories[0] = 0;
        categories[1] = 1;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 2;
        percentages[1] = 999;
        address[] memory receivers = new address[](2);
        receivers[0] = makeAddr("receiver0");
        receivers[1] = makeAddr("receiver1");

        // Revert because sum of percentages is 100.1% which is not 100%
        vm.expectRevert(ISeamEmissionManager.InvalidPercentageSum.selector);
        emissionManager.setCategoryPercetagesAndReceivers(categories, percentages, receivers);
    }

    function test_Claim() public {
        deal(seam, address(emissionManager), type(uint256).max);

        string memory description = "ILM LPs";
        uint256 minPercentage = 4;
        uint256 maxPercentage = 400;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        description = "ILM LPs 2";
        minPercentage = 5;
        maxPercentage = 1000;
        emissionManager.addNewCategory(description, minPercentage, maxPercentage);

        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        uint256[] memory categories = new uint256[](2);
        categories[0] = 0;
        categories[1] = 1;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 100;
        percentages[1] = 900;
        address[] memory receivers = new address[](2);
        receivers[0] = receiver1;
        receivers[1] = receiver2;
        emissionManager.setCategoryPercetagesAndReceivers(categories, percentages, receivers);

        // We go 5000 seconds in time, emissions are set to 1 token per second which means that until now 5000 tokens should be emitted and ready to claiming
        vm.warp(block.timestamp + 5000);
        emissionManager.claim(0);
        emissionManager.claim(1);

        // First category has 10% and second category has 90% of all emissions
        assertEq(IERC20(seam).balanceOf(receiver1), 500 ether);
        assertEq(IERC20(seam).balanceOf(receiver2), 4500 ether);
    }
}
