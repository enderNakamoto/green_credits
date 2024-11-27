// test/CarbonCredits.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Controller.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CarbonCreditsTest is Test {
    Controller public controller;
    MockUSDC public usdc;

    address public admin = address(1);
    address public priceOracle = address(2);
    address public driver = address(3);
    address public buyer = address(4);

    string constant TEST_VIN = "1HGCM82633A123456";

    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();

        // Deploy main contract
        vm.prank(admin);
        controller = new Controller(address(usdc), priceOracle);

        // Setup initial balances
        usdc.transfer(buyer, 1000 * 10**6); // 1000 USDC
    }

    function testPriceUpdate() public {
        uint256 newPrice = 150 * 10**6; // 150 USDC
        
        // Should fail if not price oracle
        vm.expectRevert("Only price oracle");
        controller.updatePrice(newPrice);
        
        // Should succeed with price oracle
        vm.prank(priceOracle);
        controller.updatePrice(newPrice);
        
        (uint256 currentPrice,) = controller.getCurrentPrice();
        assertEq(currentPrice, newPrice);
    }

    function testVehicleRegistration() public {
        vm.startPrank(admin);
        controller.registerVehicle(driver, TEST_VIN);
        
        (,, bool isRegistered) = controller.getVehicleInfo(TEST_VIN);
        assertTrue(isRegistered);
        assertEq(controller.addressToVin(driver), TEST_VIN);
        vm.stopPrank();
    }

    function testFailDuplicateVehicleRegistration() public {
        vm.startPrank(admin);
        controller.registerVehicle(driver, TEST_VIN);
        vm.expectRevert("Address already has vehicle");
        controller.registerVehicle(driver, "OTHER_VIN");
        vm.stopPrank();
    }

    function testOdometerProcessing() public {
        // Register vehicle
        vm.prank(admin);
        controller.registerVehicle(driver, TEST_VIN);

        // Process initial odometer reading
        vm.prank(admin);
        controller.processOdometerReading(driver, 1000);

        // Process new reading that should generate credits (300 miles = 3 credits)
        vm.prank(admin);
        controller.processOdometerReading(driver, 1300);

        (uint256 balance,,,,) = controller.getCreditStats(driver);
        assertEq(balance, 3);
    }

    function testCreditBurning() public {
        // Setup
        vm.prank(admin);
        controller.registerVehicle(driver, TEST_VIN);

        // Generate credits
        vm.prank(admin);
        controller.processOdometerReading(driver, 1000);
        vm.prank(admin);
        controller.processOdometerReading(driver, 1300); // 3 credits

        // Update price before burning
        vm.prank(priceOracle);
        controller.updatePrice(150 * 10**6); // 150 USDC

        // Approve USDC spending
        uint256 burnAmount = 2;
        uint256 cost = burnAmount * 150 * 10**6; // 2 credits * 150 USDC
        vm.prank(buyer);
        usdc.approve(address(controller), cost);

        // Burn credits
        vm.prank(buyer);
        controller.burnCredit(burnAmount);

        // Check balances
        (