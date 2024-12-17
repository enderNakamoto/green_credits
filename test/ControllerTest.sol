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

    function test_Deployment() view public {
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

    function test_RoundDownToNearestHundred() public view {
        uint256 rounded;
        
        // Test exact hundreds
        rounded = controller._roundDownToNearestHundred(100);
        assertEq(rounded, 100);
        
        rounded = controller._roundDownToNearestHundred(1000);
        assertEq(rounded, 1000);
        
        // Test numbers that need rounding
        rounded = controller._roundDownToNearestHundred(199);
        assertEq(rounded, 100);
        
        rounded = controller._roundDownToNearestHundred(17899);
        assertEq(rounded, 17800);
        
        rounded = controller._roundDownToNearestHundred(18113);
        assertEq(rounded, 18100);
        
        // Test edge cases
        rounded = controller._roundDownToNearestHundred(0);
        assertEq(rounded, 0);
        
        rounded = controller._roundDownToNearestHundred(99);
        assertEq(rounded, 0);
    }

    function test_CalculateCreditsEarned() public {
        uint256 credits;
        
        // Test exact multiples of MILES_PER_CREDIT (100)
        credits = controller._calculateCreditsEarned(300, 0);
        assertEq(credits, 3);
        
        credits = controller._calculateCreditsEarned(18100, 17800);
        assertEq(credits, 3);
        
        // Test incomplete miles (should round down)
        credits = controller._calculateCreditsEarned(399, 0);
        assertEq(credits, 3);
        
        credits = controller._calculateCreditsEarned(450, 300);
        assertEq(credits, 1);
        
        // Test small differences
        credits = controller._calculateCreditsEarned(99, 0);
        assertEq(credits, 0);
        
        credits = controller._calculateCreditsEarned(199, 100);
        assertEq(credits, 0);
        
        // Test edge cases
        vm.expectRevert("Invalid reading difference");
        controller._calculateCreditsEarned(100, 200);
        
        vm.expectRevert("Invalid reading difference");
        controller._calculateCreditsEarned(0, 0);
    }

    function test_OdometerProcessing() public {
        string memory vin = "VIN123";
        
        // Register vehicle
        vm.prank(owner);
        controller.registerVehicle(driver1, vin);
        
        vm.startPrank(owner);
        
        // First reading 17899 -> should be processed as 17800
        vm.expectEmit(true, false, false, true);
        emit CreditMinted(driver1, 178, vin, 17800); // 17800/100 = 178 credits
        controller.processOdometerReading(driver1, 17899);
        
        // Verify state after first reading
        (uint256 lastOdometer, uint256 lastTimestamp,) = controller.getVehicleInfo(vin);
        assertEq(lastOdometer, 17800, "First reading should be stored as 17800");
        assertEq(lastTimestamp, block.timestamp);
        
        // Check credit balance after first reading
        (uint256 balance, uint256 minted,,, string memory vinCheck) = controller.getCreditStats(driver1);
        assertEq(balance, 178, "Should have 178 credits");
        assertEq(minted, 178, "Should have minted 178 credits");
        assertEq(vinCheck, vin);
        
        // Second reading 18113 -> should be processed as 18100
        vm.expectEmit(true, false, false, true);
        emit CreditMinted(driver1, 3, vin, 300); // (18100-17800)/100 = 3 credits
        controller.processOdometerReading(driver1, 18113);
        
        // Verify state after second reading
        (lastOdometer, lastTimestamp,) = controller.getVehicleInfo(vin);
        assertEq(lastOdometer, 18100, "Second reading should be stored as 18100");
        assertEq(lastTimestamp, block.timestamp);
        
        // Check updated credit balance
        (balance, minted,,,) = controller.getCreditStats(driver1);
        assertEq(balance, 181, "Should have 181 total credits");
        assertEq(minted, 181, "Should have minted 181 total credits");
        
        vm.stopPrank();
    }

    function test_OdometerProcessingErrors() public {
        string memory vin = "VIN123";
        
        // Try to process reading for unregistered vehicle
        vm.prank(owner);
        vm.expectRevert("No registered vehicle");
        controller.processOdometerReading(driver1, 1000);
        
        // Register vehicle
        vm.prank(owner);
        controller.registerVehicle(driver1, vin);
        
        vm.startPrank(owner);
        
        // Process first reading
        controller.processOdometerReading(driver1, 17899);
        
        // Try to process lower reading
        vm.expectRevert("New reading must be higher than last processed");
        controller.processOdometerReading(driver1, 17800);
        
        // Try to process same reading rounded down
        vm.expectRevert("New reading must be higher than last processed");
        controller.processOdometerReading(driver1, 17899);
        
        vm.stopPrank();
    }

    function test_OdometerProcessingSmallIncrements() public {
        string memory vin = "VIN123";
        
        // Register vehicle
        vm.prank(owner);
        controller.registerVehicle(driver1, vin);
        
        vm.startPrank(owner);
        
        // Process reading with small increment that rounds to same hundred
        controller.processOdometerReading(driver1, 150);
        (uint256 lastOdometer,,) = controller.getVehicleInfo(vin);
        assertEq(lastOdometer, 100);
        
        // Process reading with increment less than 100
        controller.processOdometerReading(driver1, 250);
        (lastOdometer,,) = controller.getVehicleInfo(vin);
        assertEq(lastOdometer, 200);
        
        // Check credits - should have 2 credits total (200/100)
        (uint256 balance,,,, ) = controller.getCreditStats(driver1);
        assertEq(balance, 2);
        
        vm.stopPrank();
    }

    function test_BurnCredit() public {
        string memory vin = "VIN123";
        
        // Setup: Register vehicle and generate credits
        vm.prank(owner);
        controller.registerVehicle(driver1, vin);
        
        vm.prank(owner);
        controller.processOdometerReading(driver1, 17899); // Will generate 178 credits
        
        // Prepare buyer with USDC approval
        vm.startPrank(buyer);
        usdc.approve(address(controller), 1000 * 10**6); // Approve 1000 USDC
        
        // Burn 3 credits
        vm.expectEmit(true, true, false, true);
        emit CreditBurned(buyer, driver1, 1); // Will emit 3 times
        controller.burnCredit(3);
        
        // Verify states
        (uint256 buyerBalance, uint256 buyerMinted, uint256 buyerBurned,,) = controller.getCreditStats(buyer);
        (uint256 sellerBalance, uint256 sellerMinted, uint256 sellerBurned,,) = controller.getCreditStats(driver1);
        
        assertEq(buyerBalance, 3, "Buyer should have 3 credits");
        assertEq(buyerBurned, 3, "Buyer should have burned 3 credits");
        assertEq(buyerMinted, 0, "Buyer should have minted 0 credits");
        
        assertEq(sellerBalance, 175, "Seller should have 175 credits (178-3)");
        assertEq(sellerMinted, 178, "Seller minted credits should remain 178");
        assertEq(sellerBurned, 0, "Seller should have burned 0 credits");
        
        // Verify USDC transfers
        assertEq(usdc.balanceOf(buyer), 9700 * 10**6, "Buyer should have paid 300 USDC");
        
        vm.stopPrank();
    }

    function test_BurnCreditErrors() public {
        string memory vin = "VIN123";
        
        // Setup: Register vehicle and generate credits
        vm.prank(owner);
        controller.registerVehicle(driver1, vin);
        
        vm.prank(owner);
        controller.processOdometerReading(driver1, 17899); // Will generate 178 credits
        
        vm.startPrank(buyer);
        
        // Try to burn 0 credits
        vm.expectRevert("Amount must be greater than 0");
        controller.burnCredit(0);
        
        // Try to burn more credits than available
        vm.expectRevert("Not enough credits");
        controller.burnCredit(179);
        
        // Try to burn without USDC approval
        vm.expectRevert();
        controller.burnCredit(1);
        
        // Approve small amount but try to burn more
        usdc.approve(address(controller), 50 * 10**6); // Approve 50 USDC
        vm.expectRevert();
        controller.burnCredit(2); // Tries to spend 200 USDC
        
        vm.stopPrank();
    }

    function test_MultipleBurnCredits() public {
        string memory vin1 = "VIN123";
        string memory vin2 = "VIN456";
        
        // Setup: Register vehicles and generate credits
        vm.startPrank(owner);
        controller.registerVehicle(driver1, vin1);
        controller.registerVehicle(driver2, vin2);
        
        // Generate credits for both drivers
        controller.processOdometerReading(driver1, 300); // 3 credits
        controller.processOdometerReading(driver2, 200); // 2 credits
        vm.stopPrank();
        
        // Burn credits
        vm.startPrank(buyer);
        usdc.approve(address(controller), 1000 * 10**6);
        
        // Burn 4 credits (should take 3 from driver1 and 1 from driver2)
        controller.burnCredit(4);
        
        // Verify states
        (uint256 buyerBalance,, uint256 buyerBurned,,) = controller.getCreditStats(buyer);
        (uint256 driver1Balance,,,,) = controller.getCreditStats(driver1);
        (uint256 driver2Balance,,,,) = controller.getCreditStats(driver2);
        
        assertEq(buyerBalance, 4, "Buyer should have 4 credits");
        assertEq(buyerBurned, 4, "Buyer should have burned 4 credits");
        assertEq(driver1Balance, 0, "Driver1 should have 0 credits");
        assertEq(driver2Balance, 1, "Driver2 should have 1 credit");
        
        // Try to burn more - should fail as only 1 credit left
        vm.expectRevert("Not enough credits");
        controller.burnCredit(2);
        
        vm.stopPrank();
    }

    function test_WithdrawRewards() public {
        string memory vin = "VIN123";
        
        // Setup: Register vehicle and generate credits
        vm.startPrank(owner);
        controller.registerVehicle(driver1, vin);
        controller.processOdometerReading(driver1, 17899); // 178 credits
        vm.stopPrank();
        
        // Buyer burns credits which generates rewards
        vm.startPrank(buyer);
        usdc.approve(address(controller), 1000 * 10**6);
        controller.burnCredit(5);
        vm.stopPrank();
        
        // Driver1 withdraws rewards
        uint256 initialBalance = usdc.balanceOf(driver1);
        
        vm.expectEmit(true, false, false, true);
        emit RewardWithdrawn(driver1, 500 * 10**6); // 5 credits * 100 USDC
        
        vm.prank(driver1);
        controller.withdrawRewards();
        
        // Verify USDC transfer
        assertEq(
            usdc.balanceOf(driver1), 
            initialBalance + 500 * 10**6, 
            "Incorrect USDC transfer amount"
        );
    }

    function test_WithdrawRewardsMultipleBurns() public {
        string memory vin = "VIN123";
        
        // Setup: Generate credits
        vm.startPrank(owner);
        controller.registerVehicle(driver1, vin);
        controller.processOdometerReading(driver1, 17899); // 178 credits
        vm.stopPrank();
        
        // Multiple burns by different buyers
        vm.startPrank(buyer);
        usdc.approve(address(controller), 1000 * 10**6);
        controller.burnCredit(3); // 300 USDC reward
        vm.stopPrank();
        
        address buyer2 = makeAddr("buyer2");
        vm.startPrank(owner);
        usdc.transfer(buyer2, 1000 * 10**6);
        vm.stopPrank();
        
        vm.startPrank(buyer2);
        usdc.approve(address(controller), 1000 * 10**6);
        controller.burnCredit(2); // Additional 200 USDC reward
        vm.stopPrank();
        
        // Withdraw total rewards
        uint256 initialBalance = usdc.balanceOf(driver1);
        
        vm.expectEmit(true, false, false, true);
        emit RewardWithdrawn(driver1, 500 * 10**6); // 500 USDC total rewards
        
        vm.prank(driver1);
        controller.withdrawRewards();
        
        assertEq(
            usdc.balanceOf(driver1), 
            initialBalance + 500 * 10**6,
            "Incorrect total USDC transfer"
        );
    }

    function test_WithdrawZeroRewards() public {
        // Try to withdraw without any rewards
        vm.prank(driver1);
        vm.expectRevert("No rewards to withdraw");
        controller.withdrawRewards();
    }

    function test_WithdrawRewardsMultipleDrivers() public {
        // Setup: Register vehicles and generate credits
        vm.startPrank(owner);
        controller.registerVehicle(driver1, "VIN123");
        controller.registerVehicle(driver2, "VIN456");
        controller.processOdometerReading(driver1, 300); // 3 credits
        controller.processOdometerReading(driver2, 200); // 2 credits
        vm.stopPrank();
        
        // Buyer burns all available credits
        vm.startPrank(buyer);
        usdc.approve(address(controller), 1000 * 10**6);
        controller.burnCredit(5);
        vm.stopPrank();
        
        // Both drivers withdraw their rewards
        uint256 driver1InitialBalance = usdc.balanceOf(driver1);
        uint256 driver2InitialBalance = usdc.balanceOf(driver2);
        
        vm.prank(driver1);
        controller.withdrawRewards();
        
        vm.prank(driver2);
        controller.withdrawRewards();
        
        // Verify correct reward distribution
        assertEq(
            usdc.balanceOf(driver1), 
            driver1InitialBalance + 300 * 10**6, 
            "Driver1 incorrect reward"
        );
        assertEq(
            usdc.balanceOf(driver2), 
            driver2InitialBalance + 200 * 10**6,
            "Driver2 incorrect reward"
        );
    }

    function test_WithdrawRewardsMultipleTimes() public {
        string memory vin = "VIN123";
        
        // Setup: Generate credits
        vm.startPrank(owner);
        controller.registerVehicle(driver1, vin);
        controller.processOdometerReading(driver1, 300); // 3 credits
        vm.stopPrank();
        
        // First burn and withdraw
        vm.startPrank(buyer);
        usdc.approve(address(controller), 1000 * 10**6);
        controller.burnCredit(2);
        vm.stopPrank();
        
        vm.prank(driver1);
        controller.withdrawRewards();
        
        // Second burn and withdraw
        vm.startPrank(buyer);
        controller.burnCredit(1);
        vm.stopPrank();
        
        vm.prank(driver1);
        controller.withdrawRewards();
        
        // Try to withdraw again with no rewards
        vm.prank(driver1);
        vm.expectRevert("No rewards to withdraw");
        controller.withdrawRewards();
    }    

}