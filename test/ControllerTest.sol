// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Controller.sol";
import "../test/MockUSDC.sol";

contract ControllerTest is Test {
    Controller public controller;
    MockUSDC public usdc;
    address public owner;
    address public priceOracle;
    address public driver1;
    address public driver2;
    address public buyer;

    event CreditMinted(address indexed holder, uint256 amount, string vin, uint256 milesDriven);
    event CreditBurned(address indexed burner, address indexed seller, uint256 amount);
    event RewardWithdrawn(address indexed holder, uint256 amount);
    event VehicleRegistered(address indexed owner, string vin);
    event PriceUpdated(uint256 newPrice, uint256 timestamp);

    function setUp() public {
        owner = makeAddr("owner");
        priceOracle = makeAddr("priceOracle");
        driver1 = makeAddr("driver1");
        driver2 = makeAddr("driver2");
        buyer = makeAddr("buyer");

        vm.startPrank(owner);
        
        // Deploy contracts
        usdc = new MockUSDC();
        controller = new Controller(address(usdc), priceOracle);
        
        // Since MockUSDC mints to the deployer (owner), we can now transfer
        usdc.transfer(buyer, 10000 * 10**6); // 10k USDC
        
        vm.stopPrank();
    }

    function test_Deployment() public {
        assertEq(address(controller.usdc()), address(usdc));
        assertEq(controller.priceOracle(), priceOracle);
        assertEq(controller.creditPrice(), 100 * 10**6); // 100 USDC
        assertEq(controller.owner(), owner);
    }

    function test_VehicleRegistration() public {
        string memory vin = "VIN123";
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit VehicleRegistered(driver1, vin);
        controller.registerVehicle(driver1, vin);

        assertTrue(controller.registeredVins(vin));
        assertEq(controller.addressToVin(driver1), vin);
        
        (uint256 lastOdometer, uint256 lastTimestamp, bool isRegistered) = controller.getVehicleInfo(vin);
        assertEq(lastOdometer, 0);
        assertEq(lastTimestamp, block.timestamp);
        assertTrue(isRegistered);
    }

    function test_DuplicateRegistrationFails() public {
        string memory vin = "VIN123";
        
        vm.startPrank(owner);
        controller.registerVehicle(driver1, vin);
        
        vm.expectRevert("VIN already registered");
        controller.registerVehicle(driver2, vin);
        
        vm.expectRevert("Address already has vehicle");
        controller.registerVehicle(driver1, "VIN456");
        vm.stopPrank();
    }

    function test_OdometerProcessing() public {
        string memory vin = "VIN123";
        
        // Register vehicle
        vm.prank(owner);
        controller.registerVehicle(driver1, vin);
        
        // Process odometer reading
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit CreditMinted(driver1, 2, vin, 250); // 250 miles = 2 credits
        controller.processOdometerReading(driver1, 250);
        
        // Verify credit balance
        (uint256 balance,,,,) = controller.getCreditStats(driver1);
        assertEq(balance, 2);
        assertEq(controller.getAvailableCredits(), 2);
    }

    function test_CreditBurning() public {
        // Setup: Register and generate credits
        string memory vin = "VIN123";
        
        vm.startPrank(owner);
        controller.registerVehicle(driver1, vin);
        controller.processOdometerReading(driver1, 250); // 2 credits
        vm.stopPrank();
        
        // Approve USDC spending
        vm.startPrank(buyer);
        usdc.approve(address(controller), 1000 * 10**6);
        
        // Burn 1 credit
        vm.expectEmit(true, true, false, true);
        emit CreditBurned(buyer, driver1, 1);
        controller.burnCredit(1);
        
        // Verify states
        (uint256 balance,,,,) = controller.getCreditStats(buyer);
        assertEq(balance, 1);
        assertEq(controller.getAvailableCredits(), 1);
        vm.stopPrank();
    }

    function test_RewardWithdrawal() public {
        // Setup: Generate and burn credits
        string memory vin = "VIN123";
        
        vm.startPrank(owner);
        controller.registerVehicle(driver1, vin);
        controller.processOdometerReading(driver1, 250); // 2 credits
        vm.stopPrank();
        
        vm.startPrank(buyer);
        usdc.approve(address(controller), 1000 * 10**6);
        controller.burnCredit(1);
        vm.stopPrank();
        
        // Withdraw rewards
        vm.prank(driver1);
        vm.expectEmit(true, false, false, true);
        emit RewardWithdrawn(driver1, 100 * 10**6); // 100 USDC reward
        controller.withdrawRewards();
        
        // Verify USDC balance
        assertEq(usdc.balanceOf(driver1), 100 * 10**6);
    }

    function test_PriceUpdate() public {
        uint256 newPrice = 150 * 10**6; // 150 USDC
        
        vm.prank(priceOracle);
        vm.expectEmit(false, false, false, true);
        emit PriceUpdated(newPrice, block.timestamp);
        controller.updatePrice(newPrice);
        
        assertEq(controller.creditPrice(), newPrice);
        
        (uint256 price, uint256 lastUpdate) = controller.getCurrentPrice();
        assertEq(price, newPrice);
        assertEq(lastUpdate, block.timestamp);
    }

    function test_UnauthorizedAccess() public {
        vm.startPrank(driver1);
        
        vm.expectRevert("Ownable: caller is not the owner");
        controller.registerVehicle(driver1, "VIN123");
        
        vm.expectRevert("Ownable: caller is not the owner");
        controller.processOdometerReading(driver1, 100);
        
        vm.expectRevert("Only price oracle");
        controller.updatePrice(150 * 10**6);
        
        vm.stopPrank();
    }

    function testFuzz_OdometerReading(uint256 mileage) public {
        vm.assume(mileage > 0 && mileage < 1000000); // Reasonable mileage range
        
        string memory vin = "VIN123";
        
        vm.startPrank(owner);
        controller.registerVehicle(driver1, vin);
        controller.processOdometerReading(driver1, mileage);
        
        uint256 expectedCredits = mileage / controller.MILES_PER_CREDIT();
        (uint256 balance,,,,) = controller.getCreditStats(driver1);
        assertEq(balance, expectedCredits);
        
        vm.stopPrank();
    }

    // function test_ComplexScenario() public {
    //     // Setup multiple drivers and vehicles
    //     string memory vin1 = "VIN123";
    //     string memory vin2 = "VIN456";
        
    //     vm.startPrank(owner);
    //     controller.registerVehicle(driver1, vin1);
    //     controller.registerVehicle(driver2, vin2);
        
    //     // Process different mileages
    //     controller.processOdometerReading(driver1, 350); // 3 credits
    //     controller.processOdometerReading(driver2, 250); // 2 credits
    //     vm.stopPrank();
        
    //     // Buyer burns credits from both drivers
    //     vm.startPrank(buyer);
    //     usdc.approve(address(controller), 1000 * 10**6);
    //     controller.burnCredit(2); // Should get 1 from each driver
    //     vm.stopPrank();
        
    //     // Both drivers withdraw rewards
    //     vm.prank(driver1);
    //     controller.withdrawRewards();
    //     vm.prank(driver2);
    //     controller.withdrawRewards();
        
    //     // Verify final states
    //     (uint256 balance1,,,,) = controller.getCreditStats(driver1);
    //     (uint256 balance2,,,,) = controller.getCreditStats(driver2);
    //     assertEq(balance1, 2);
    //     assertEq(balance2, 1);
    //     assertEq(usdc.balanceOf(driver1), 100 * 10**6);
    //     assertEq(usdc.balanceOf(driver2), 100 * 10**6);
    //     assertEq(usdc.balanceOf(buyer), 9800 * 10**6);
    // }
}